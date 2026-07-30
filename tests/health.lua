-- Health assertions for the config. Run via tests/run.sh, which supplies the
-- mandatory -u flag:
--   NVIM_APPNAME=nvim-dev nvim --headless -u ~/.config/nvim-dev/init.lua -l tests/health.lua
-- Exits 0 when all checks pass, 1 otherwise.

local failures = {}

---@param name string
---@param ok boolean
---@param msg? string
local function check(name, ok, msg)
  if ok then
    print(('  ok   %s'):format(name))
  else
    failures[#failures + 1] = name
    print(('  FAIL %s%s'):format(name, msg and (': ' .. msg) or ''))
  end
end

print '== environment =='
-- has('nvim-0.12') rather than vim.version.ge(): semver ranks a prerelease
-- below its release, so ge(0.12.0-dev, 0.12) is false on nightly builds even
-- though they have the 0.12 APIs this config needs. Verified.
check('neovim >= 0.12', vim.fn.has 'nvim-0.12' == 1, tostring(vim.version()))
check(
  'vim.pack available',
  type(vim.pack) == 'table' and type(vim.pack.add) == 'function',
  ('vim.pack=%s add=%s'):format(type(vim.pack), type(vim.pack) == 'table' and type(vim.pack.add) or 'n/a')
)
check('vim.lsp.config available', type(vim.lsp.config) == 'table' or type(vim.lsp.config) == 'function', ('type=%s'):format(type(vim.lsp.config)))
check('running under nvim-dev', vim.fn.stdpath('config'):match 'nvim%-dev' ~= nil, vim.fn.stdpath 'config')

-- HARNESS SELF-CHECK. `nvim -l` skips user config unless -u is given, so
-- without it init.lua never runs and every check below would pass or fail for
-- the wrong reason. `vim.g.config_sentinel` is set by the first line of the new
-- init.lua (Task 2); its absence means the suite is testing nothing.
--
-- Expect this to fail until Task 2 replaces init.lua. That is the intended red
-- state, not a broken harness.
check(
  'init.lua ran (harness wired correctly)',
  vim.g.config_sentinel == true,
  'sentinel missing -- run via tests/run.sh, or init.lua not yet rewritten (Task 2)'
)

-- Two sentinels, deliberately. config_sentinel is set on init.lua's FIRST line
-- and config_loaded on its LAST, so the pair distinguishes three states:
--   neither  -> harness unwired (-u missing); nothing below means anything
--   first    -> init.lua started but ERRORED partway (headless nvim reports the
--               error and carries on, so this would otherwise look healthy)
--   both     -> init.lua completed
-- Without the second sentinel a mid-file error is invisible, and that becomes
-- the most likely regression as init.lua grows to a dozen requires.
check('init.lua completed without error', vim.g.config_loaded == true, 'init.lua errored partway -- check :messages at real startup')

-- WIRING vs STATE. This loop requires each module itself, which applies its
-- side effects. So the option assertions further down would pass even if
-- init.lua had stopped requiring config.options entirely -- verified: commenting
-- out that require left six checks green.
--
-- Capture what init.lua ALREADY loaded, before this loop pollutes package.loaded,
-- so the two properties can be asserted separately.
local preloaded = {}
for _, mod in ipairs { 'config.options', 'config.keymaps', 'config.autocmds', 'config.diagnostics', 'config.brazil' } do
  preloaded[mod] = package.loaded[mod] ~= nil
end

print '== init.lua wiring =='
check('init.lua requires config.options', preloaded['config.options'], 'init.lua never loaded it; the option checks below would still pass')

print '== modules load =='
for _, mod in ipairs {
  'config.options',
  'config.keymaps',
  'config.autocmds',
  'config.diagnostics',
  'config.brazil',
} do
  local ok, err = pcall(require, mod)
  check('require ' .. mod, ok, tostring(err))
end

print '== options =='
check('leader is space', vim.g.mapleader == ' ', tostring(vim.g.mapleader))
check('nerd font enabled', vim.g.have_nerd_font == true, tostring(vim.g.have_nerd_font))
check('number on', vim.o.number == true)
check('relativenumber on', vim.o.relativenumber == true)
check('undofile on', vim.o.undofile == true)
check('signcolumn yes', vim.o.signcolumn == 'yes', vim.o.signcolumn)
check('splitright', vim.o.splitright == true)
check('termguicolors', vim.o.termguicolors == true)

-- `updatetime` must be asserted in a CHILD process, not here.
--
-- Nvim's -l scripting mode forces updatetime=1 and updatecount=0 AFTER init.lua
-- runs, to make scripts responsive. Verified: under -l the value is always 1
-- even though init.lua did set it (nvim_get_option_info2 reports was_set=true,
-- last_set_sid=5 -- the assignment is recorded, then overridden), while the same
-- config at normal startup yields 200. So an in-process check here would be
-- permanently unsatisfiable -- a test that can never go green.
--
-- updatetime is the ONLY option this suite asserts that -l overrides; the other
-- eight above survive intact (verified individually). It matters because it
-- drives CursorHold, which gates LSP document highlighting.
--
-- vim.v.progpath, not bare 'nvim': PATH may resolve to a different Neovim than
-- the one running this suite, which would silently measure the wrong binary.
-- It also avoids vim.system throwing on ENOENT, which would abort this script
-- before the summary below and lose every other check's result.
--
-- :wait(15000) bounds it -- an unbounded wait on a hung child gives no output
-- and no exit code, which is worse than a failure. Timeout surfaces as code 124.
local startup_probe = {
  vim.v.progpath,
  '--headless',
  '-u',
  vim.fn.stdpath 'config' .. '/init.lua',
  '-c',
  'lua io.write(vim.o.updatetime)',
  '-c',
  'qa',
}
local ut = vim.system(startup_probe, { text = true }):wait(15000)

-- Exact comparison on the trimmed output, not a substring match: `match '200'`
-- would also accept 1200 or 2001.
local ut_value = (ut.stdout or ''):gsub('%s', '')
check('updatetime 200 (measured at real startup)', ut_value == '200', ('child reported %q, code %s'):format(ut_value, tostring(ut.code)))

-- This child is the suite's ONLY observation of a real (non -l) startup, so it
-- is also the only place that can catch a config that errors on load. Headless
-- nvim prints the error to stderr and keeps going, so without these two checks a
-- broken config still prints 200 and goes green.
check('real startup exits clean', ut.code == 0, tostring(ut.code))
check('real startup emits no errors', not (ut.stderr or ''):match 'E%d+', ut.stderr)

print '== keymaps =='

---Returns true if a normal-mode mapping for `lhs` exists.
---
--- Two storage quirks, both verified against nvim_get_keymap:
---   * `<leader>x` is stored with the leader ALREADY EXPANDED to its literal
---     character. With a space leader, `<leader>bd` is stored as `" bd"`
---     (bytes 32,98,100) -- NOT as `"<Space>bd"`. Comparing against
---     `"<Space>bd"` can never match.
---   * Control keys are stored uppercased: `<C-h>` is stored as `"<C-H>"`.
--- This helper normalises a `<leader>` prefix so callers can write the
--- readable form.
---@param lhs string
---@return boolean
local function has_nmap(lhs)
  local want = lhs:gsub('^<leader>', vim.g.mapleader or ' ')
  for _, m in ipairs(vim.api.nvim_get_keymap 'n') do
    if m.lhs == want then return true end
  end
  return false
end

for _, lhs in ipairs { '<C-H>', '<C-L>', '<C-J>', '<C-K>', '<leader>bd' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end

print '== autocmds =='

---Counts autocmds in an augroup, returning 0 when the group does not exist.
---
--- nvim_get_autocmds THROWS `E5113: Invalid 'group'` for an unknown group rather
--- than returning an empty list (verified). Called bare, a missing augroup would
--- abort this script mid-run -- losing the summary and every check after it -- so
--- the failure would present as truncated output rather than a named FAIL.
---@param group string
---@param event? string
---@return integer
local function count_autocmds(group, event)
  local ok, result = pcall(vim.api.nvim_get_autocmds, { group = group, event = event })
  return ok and #result or 0
end

check('yank highlight augroup', count_autocmds('config-highlight-yank', 'TextYankPost') > 0, 'augroup missing or empty')

-- The five augroups config.autocmds creates. Asserted together because the test
-- above covers only one, and a silently-missing autocmd is invisible in normal use.
for _, group in ipairs { 'highlight-yank', 'last-loc', 'close-with-q', 'auto-create-dir', 'term-open' } do
  local n = count_autocmds('config-' .. group)
  check('augroup config-' .. group, n > 0, ('%d autocmds'):format(n))
end

print '== diagnostics =='
local dcfg = vim.diagnostic.config()

check('virtual_text is a table', type(dcfg.virtual_text) == 'table', type(dcfg.virtual_text))
check(
  'virtual_text.current_line == false (all lines EXCEPT cursor line)',
  type(dcfg.virtual_text) == 'table' and dcfg.virtual_text.current_line == false,
  type(dcfg.virtual_text) == 'table' and tostring(dcfg.virtual_text.current_line) or 'n/a'
)
check('virtual_lines is a table', type(dcfg.virtual_lines) == 'table', type(dcfg.virtual_lines))
check('virtual_lines.current_line == true', type(dcfg.virtual_lines) == 'table' and dcfg.virtual_lines.current_line == true)
check('severity_sort on', dcfg.severity_sort == true)
check('update_in_insert off', dcfg.update_in_insert == false)
check('signs configured', dcfg.signs ~= false and dcfg.signs ~= nil)
check('on_jump handler set', type(dcfg.jump) == 'table' and type(dcfg.jump.on_jump) == 'function')

-- Sign glyphs must be non-empty. The plan document had these stripped to bare
-- spaces at one point, and Neovim silently accepts an empty sign text -- so a
-- length check is the only way to catch it.
if type(dcfg.signs) == 'table' and type(dcfg.signs.text) == 'table' then
  for _, sev in ipairs { 'ERROR', 'WARN', 'INFO', 'HINT' } do
    local glyph = dcfg.signs.text[vim.diagnostic.severity[sev]]
    check(('sign glyph %s non-empty'):format(sev), type(glyph) == 'string' and glyph:gsub('%s', '') ~= '', tostring(glyph))
  end
end

for _, lhs in ipairs { 'gK', ']d', '[d', ']e', '[e', '<leader>cd' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end

print '== brazil excludes =='
local ok_brazil, brazil = pcall(require, 'config.brazil')
check('config.brazil loads', ok_brazil, tostring(brazil))
if ok_brazil then
  -- The build/ symlink is the specific cause of the measured gd latency.
  check('excludes **/build', vim.tbl_contains(brazil.exclude_globs, '**/build'))
  check('excludes **/.bemol', vim.tbl_contains(brazil.exclude_globs, '**/.bemol'))
  check('excludes **/node_modules', vim.tbl_contains(brazil.exclude_globs, '**/node_modules'))
  check('excludes **/target', vim.tbl_contains(brazil.exclude_globs, '**/target'))
  check('python root markers include Config', vim.tbl_contains(brazil.python_root_markers, 'Config'))
  check('python root markers include pyproject.toml', vim.tbl_contains(brazil.python_root_markers, 'pyproject.toml'))
  check('node root markers include tsconfig.json', vim.tbl_contains(brazil.node_root_markers, 'tsconfig.json'))
  check('exclude_globs is non-empty', #brazil.exclude_globs >= 8, tostring(#brazil.exclude_globs))
  -- Pure data: requiring it must not mutate editor state.
  check('config.brazil has no side effects', type(brazil) == 'table' and brazil.exclude_globs ~= nil)
end

if #failures > 0 then
  print(('\n%d failure(s): %s'):format(#failures, table.concat(failures, ', ')))
else
  print '\n0 failure(s)'
end
vim.cmd(#failures == 0 and 'cq 0' or 'cq 1')
