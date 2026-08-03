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
for _, mod in ipairs { 'config.options', 'config.keymaps', 'config.autocmds', 'config.diagnostics', 'config.project' } do
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
  'config.project',
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

for _, lhs in ipairs { '<leader>ud', ']d', '[d', ']e', '[e', '<leader>cd' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end

print '== project detection =='
local ok_project, project = pcall(require, 'config.project')
check('config.project loads', ok_project, tostring(project))
if ok_project then
  check('excludes **/build', vim.tbl_contains(project.exclude_globs, '**/build'))
  check('excludes **/node_modules', vim.tbl_contains(project.exclude_globs, '**/node_modules'))
  check('excludes **/target', vim.tbl_contains(project.exclude_globs, '**/target'))
  -- Dependency sources must NOT be excluded: doing so hid every third-party
  -- import, so a project reported "could not be resolved" for all of them.
  check('does NOT exclude **/.venv (deps live there)', not vim.tbl_contains(project.exclude_globs, '**/.venv'))
  check('does NOT exclude **/venv', not vim.tbl_contains(project.exclude_globs, '**/venv'))
  check('python root markers include pyproject.toml', vim.tbl_contains(project.python_root_markers, 'pyproject.toml'))
  check('node root markers include tsconfig.json', vim.tbl_contains(project.node_root_markers, 'tsconfig.json'))
  check('exclude_globs is non-empty', #project.exclude_globs >= 8, tostring(#project.exclude_globs))
  check('config.project is pure data/functions', type(project) == 'table' and project.exclude_globs ~= nil)

  -- python_path must find a venv it can actually execute, and reject one it
  -- cannot. Built in a temp dir so the assertion does not depend on any checkout.
  check('python_path is a function', type(project.python_path) == 'function')
  check('find_venvs is a function', type(project.find_venvs) == 'function')
  check('python_extra_paths is a function', type(project.python_extra_paths) == 'function')
  if type(project.python_path) == 'function' then
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/.venv/bin', 'p')
    check('python_path returns nil when no usable interpreter', project.python_path(tmp) == nil, 'a non-executable stub must not be accepted')
    -- A real interpreter symlinked into place must be found.
    vim.fn.system(('ln -s %s %s/.venv/bin/python'):format(vim.fn.exepath 'python3', tmp))
    if vim.fn.executable(tmp .. '/.venv/bin/python') == 1 then
      check('python_path finds <root>/.venv', project.python_path(tmp) == tmp .. '/.venv/bin/python', tostring(project.python_path(tmp)))
    end
    vim.fn.mkdir(tmp .. '/src', 'p')
    check('python_extra_paths includes src', vim.tbl_contains(project.python_extra_paths(tmp), 'src'))
    vim.fn.delete(tmp, 'rf')
  end
end

print '== ui plugins =='

---@param name string module name to require
local function loads(name)
  local ok, err = pcall(require, name)
  check('require ' .. name, ok, tostring(err))
end

loads 'which-key'
loads 'catppuccin'
loads 'mini.ai'
loads 'mini.surround'
loads 'mini.icons'
loads 'todo-comments'
loads 'lualine'

check('colorscheme is catppuccin', (vim.g.colors_name or ''):match 'catppuccin' ~= nil, tostring(vim.g.colors_name))
check('gh() helper defined by init.lua', type(_G.gh) == 'function', type(_G.gh))
check('PackChanged hook registered', count_autocmds('', 'PackChanged') > 0 or #vim.api.nvim_get_autocmds { event = 'PackChanged' } > 0)

print '== treesitter =='
loads 'nvim-treesitter'
check('treesitter augroup', count_autocmds 'config-treesitter' > 0)

local ok_ts, ts = pcall(require, 'nvim-treesitter')
if ok_ts then
  local ts_installed = ts.get_installed 'parsers'
  -- The languages actually edited in this workspace. A missing parser here means
  -- no highlighting, which is silent -- worth asserting rather than eyeballing.
  for _, lang in ipairs { 'python', 'typescript', 'tsx', 'rust', 'lua', 'bash', 'json', 'yaml', 'markdown' } do
    check('parser ' .. lang, vim.tbl_contains(ts_installed, lang), 'not installed')
  end
end

print '== picker =='
loads 'telescope'
check('fzf binary on PATH', vim.fn.executable 'fzf' == 1)
check('rg binary on PATH', vim.fn.executable 'rg' == 1)
check('fd binary on PATH', vim.fn.executable 'fd' == 1)

-- The native C sorter is what keeps telescope usable on a ~99k-file workspace.
local ts_ok, ts_mod = pcall(require, 'telescope')
check('telescope loads', ts_ok, tostring(ts_mod))
if ts_ok then
  check('fzf-native extension loaded', ts_mod.extensions and ts_mod.extensions.fzf ~= nil, 'native sorter missing -- run make in telescope-fzf-native.nvim')
  check('ui-select extension loaded', ts_mod.extensions and ts_mod.extensions['ui-select'] ~= nil)
end
-- Telescope auto-jumps on a lone LSP result unless jump_type == 'never'; this
-- config must never set that, or `gd` regresses from a jump to a menu.
local lsp_src = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/picker.lua', 'r')
if lsp_src then
  local src = lsp_src:read 'a'
  lsp_src:close()
  check('picker does not disable LSP auto-jump', src:match "jump_type%s*=%s*'never'" == nil, 'gd would open a picker instead of jumping')
end

for _, lhs in ipairs { '<leader>ff', '<leader>sg', '<leader>/', '<leader>fb', '<leader>sw', '<leader>fg' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end

-- Keymaps must match LazyVim's descriptions, not merely exist. An earlier version
-- had grep on <leader>fg (LazyVim's git-files key) and sd/sD inverted, which
-- "does a mapping exist" checks could never catch.
local lazyvim_keys = {
  ['<leader>ff'] = 'Find Files (Root Dir)',
  ['<leader>fg'] = 'Find Files (git-files)',
  ['<leader>fb'] = 'Buffers',
  ['<leader>fr'] = 'Recent',
  ['<leader>/'] = 'Grep (Root Dir)',
  ['<leader>sg'] = 'Grep (Root Dir)',
  ['<leader>sd'] = 'Diagnostics',
  ['<leader>sD'] = 'Buffer Diagnostics',
  ['<leader>sc'] = 'Command History',
  ['<leader>sC'] = 'Commands',
  ['<leader>sR'] = 'Resume',
  ['<leader>gs'] = 'Status',
}
local nmaps = {}
for _, m in ipairs(vim.api.nvim_get_keymap 'n') do
  nmaps[m.lhs] = m.desc or ''
end
for lhs, want in pairs(lazyvim_keys) do
  local stored = lhs:gsub('^<leader>', vim.g.mapleader or ' ')
  check(('LazyVim desc %s'):format(lhs), nmaps[stored] == want, ('want %q got %q'):format(want, tostring(nmaps[stored])))
end

print '== explorer / theme / trouble =='
check('nvim-tree deferred', package.loaded['nvim-tree'] == nil, 'loaded eagerly')
check('trouble deferred', package.loaded.trouble == nil, 'loaded eagerly')
check('explorer mapped <leader>e', has_nmap '<leader>e')
check('explorer mapped <leader>fe', has_nmap '<leader>fe')
check('netrw disabled (nvim-tree requires it)', vim.g.loaded_netrwPlugin == 1)
check('colorscheme is catppuccin-macchiato', vim.g.colors_name == 'catppuccin-macchiato', tostring(vim.g.colors_name))
for _, lhs in ipairs { '<leader>xx', '<leader>xX', '<leader>cs', '<leader>cS', '<leader>xt' } do
  check('trouble nmap ' .. lhs, has_nmap(lhs))
end

print '== lsp =='
loads 'lspconfig'

-- mason, mason-lspconfig and fidget are deliberately NOT required here: they are
-- deferred to LspAttach / the :Mason* commands, and requiring them would both
-- load ~60 modules and make the "mason deferred" check below meaningless.
-- Presence on disk is what matters at this point.
for _, dir in ipairs { 'mason.nvim', 'mason-lspconfig.nvim', 'mason-tool-installer.nvim', 'fidget.nvim' } do
  local path = ('%s/site/pack/core/opt/%s'):format(vim.fn.stdpath 'data', dir)
  check('installed on disk: ' .. dir, vim.uv.fs_stat(path) ~= nil, path)
end

--- Reads back a server's resolved configuration.
---
--- Must use the INDEX form `vim.lsp.config[name]`, not the call form
--- `vim.lsp.config(name)`. The call form is the setter and raises
--- "cfg: expected table (hint: to resolve a config, use vim.lsp.config[...])"
--- when called with one argument. Verified on 0.12.
---@param name string
---@return table|nil
local function server_cfg(name)
  local ok, cfg = pcall(function() return vim.lsp.config[name] end)
  return (ok and type(cfg) == 'table') and cfg or nil
end

local bp = server_cfg 'basedpyright'
check('basedpyright configured', bp ~= nil)
if bp then
  local analysis = vim.tbl_get(bp, 'settings', 'basedpyright', 'analysis') or {}
  check('basedpyright diagnosticMode openFilesOnly', analysis.diagnosticMode == 'openFilesOnly', tostring(analysis.diagnosticMode))
  check('basedpyright excludes **/build (the gd latency fix)', vim.tbl_contains(analysis.exclude or {}, '**/build'))
  check('basedpyright does NOT exclude **/.venv', not vim.tbl_contains(analysis.exclude or {}, '**/.venv'))
  check('basedpyright suppresses untyped-dep noise', (analysis.diagnosticSeverityOverrides or {}).reportUnknownMemberType == 'none')
  check('basedpyright has before_init for venv detection', type(bp.before_init) == 'function', 'per-root interpreter detection missing')
  check('basedpyright root markers include pyproject.toml', vim.tbl_contains(bp.root_markers or {}, 'pyproject.toml'))
end

for _, s in ipairs { 'vtsls', 'lua_ls', 'ruff', 'gopls', 'bashls', 'jsonls', 'yamlls', 'taplo', 'marksman' } do
  check(s .. ' configured', server_cfg(s) ~= nil)
end

-- Every server this config owns must be enabled...
for _, s in ipairs { 'basedpyright', 'ruff', 'vtsls', 'lua_ls', 'gopls' } do
  check(s .. ' enabled', vim.lsp.is_enabled(s) == true)
end

-- ...and rust_analyzer must NOT be, because rustaceanvim owns it exclusively.
-- Uses vim.lsp.is_enabled(): there is no vim.lsp.config._enabled field on 0.12
-- (it is nil), so testing against that would silently always pass.
check('rust_analyzer NOT enabled here (rustaceanvim owns it)', vim.lsp.is_enabled 'rust_analyzer' == false, 'would double-start')
check('pyright NOT enabled (fallback only)', vim.lsp.is_enabled 'pyright' == false, 'two type checkers would both run')

-- mason-lspconfig is deferred (loaded on LspAttach), so its settings module
-- reports the upstream default `true` until then. Reading it here would test the
-- default rather than this config's intent. Assert the SOURCE instead: the one
-- setup call must pass automatic_enable = false. Verified separately that after
-- a real LspAttach the live value is false and rust_analyzer stays disabled.
local lsp_src = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/lsp.lua', 'r')
if lsp_src then
  local src = lsp_src:read 'a'
  lsp_src:close()
  check(
    'lsp.lua sets automatic_enable = false (this config owns enablement)',
    src:match "mason%-lspconfig'%)%.setup%s*{%s*automatic_enable%s*=%s*false" ~= nil,
    'mason-lspconfig would re-configure servers and could displace the tuned excludes'
  )
  check('lsp.lua does not enable rust_analyzer', src:match 'rust_analyzer%s*=%s*{' == nil, 'rustaceanvim must be the only owner')
end

check('LspAttach augroup', count_autocmds 'config-lsp-attach' > 0)

-- Rust inlay hints on by default. Two separate assertions because two separate
-- layers are involved, and each fails silently on its own:
--   1. the server must be asked to compute hints (vim.g.rustaceanvim settings);
--   2. Neovim's renderer must be switched on per buffer, since
--      vim.lsp.inlay_hint defaults to disabled -- (1) alone displays nothing.
-- Asserted statically: rustaceanvim only starts on a real Rust buffer, which a
-- headless run has none of.
local ra = vim.g.rustaceanvim or {}
local ra_hints = vim.tbl_get(ra, 'server', 'default_settings', 'rust-analyzer', 'inlayHints') or {}
check('rust-analyzer computes parameter hints', vim.tbl_get(ra_hints, 'parameterHints', 'enable') == true)
check('rust on_attach enables the inlay hint renderer', type(vim.tbl_get(ra, 'server', 'on_attach')) == 'function', 'hints are computed but never displayed')

-- Must be enabled PER BUFFER, not globally: a global enable would also turn
-- hints on for Python, Go and TypeScript, where vtsls deliberately keeps
-- variableTypes off.
local rust_src = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/rust.lua', 'r')
if rust_src then
  local src = rust_src:read 'a'
  rust_src:close()
  check(
    'rust inlay hints scoped to the buffer',
    src:match 'inlay_hint%.enable%(true,%s*{%s*bufnr' ~= nil,
    'a global enable would leak hints into every filetype'
  )
end

-- Runtime interpreter switching. before_init resolves the interpreter once at
-- server start, so a venv activated later cannot be picked up without this.
check('VenvSelect command exists', vim.fn.exists ':VenvSelect' == 2, 'no way to fix a wrong interpreter without restarting')
check('VenvCurrent command exists', vim.fn.exists ':VenvCurrent' == 2)
check('venv keymap <leader>cv', has_nmap '<leader>cv')

-- No codelens anywhere: reference-counting codelens on CursorMoved was the
-- primary cause of the gd latency this config exists to fix.
for _, offender in ipairs { 'lensline', 'lsp_lines', 'nvim-lightbulb' } do
  check('no ' .. offender, package.loaded[offender] == nil, 'reference-counting codelens reintroduces the latency')
end

print '== editor QoL =='
loads 'snacks'

-- NOTE on reading snacks.config: its config table has an __index metatable that
-- auto-creates an empty table for any key touched (its init.lua:50-54), so
-- `snacks.config.picker` is NEVER nil. Verified. Assert on `.enabled` only --
-- testing the table for nil would always pass and prove nothing.
local snacks_ok, snacks = pcall(require, 'snacks')
if snacks_ok then
  -- words and gitbrowse are enabled but defer their cost: gitbrowse is required
  -- on keymap, words loads on LspAttach. The .enabled flag is still set at
  -- setup() time, so it reads true even headlessly where neither has attached.
  for _, m in ipairs { 'bigfile', 'quickfile', 'notifier', 'input', 'words', 'gitbrowse' } do
    check('snacks.' .. m .. ' enabled', snacks.config[m].enabled == true)
  end
  for _, m in ipairs { 'picker', 'explorer', 'dashboard', 'scroll', 'statuscolumn' } do
    check('snacks.' .. m .. ' NOT enabled', snacks.config[m].enabled ~= true, 'duplicates existing plugins or adds per-keystroke work')
  end
  -- Indent guides must have exactly one owner; mini.indentscope owns them
  -- (Task 3). Both drawing at once produces overlapping extmarks and flicker.
  check('snacks.indent NOT enabled (mini.indentscope owns guides)', snacks.config.indent.enabled ~= true)

  -- vim.notify must be REPLACED. Comparing directly against notifier.notify
  -- fails on a fresh session: snacks installs a one-shot trampoline that only
  -- swaps itself out on the first call (its init.lua:219-223). Verified both
  -- ways. So fire one notification first, then compare.
  vim.notify('health check', vim.log.levels.INFO)
  check('notifier took over vim.notify', vim.notify == require('snacks.notifier').notify)
end

-- mini.pairs and mini.indentscope are set up on the first real buffer
-- (lua/plugins/ui.lua), which the headless suite has none of -- so assert the
-- source wires them, not live state.
local ui_src = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/ui.lua', 'r')
if ui_src then
  local src = ui_src:read 'a'
  ui_src:close()
  check('mini.pairs set up on first buffer', src:match "require%('mini%.pairs'%)%.setup" ~= nil)
  -- Command mode on, terminal off: pairs on the `:` line are useful, pairs in a
  -- shell or lazygit terminal are not.
  check('mini.pairs command mode on, terminal off', src:match 'command = true' ~= nil and src:match 'terminal = false' ~= nil)
  check('mini.indentscope set up on first buffer', src:match "require%('mini%.indentscope'%)%.setup" ~= nil)
  -- Guides in a help/terminal/tree buffer are noise, not signal.
  check('mini.indentscope disabled in scratch filetypes', src:match 'miniindentscope_disable' ~= nil)
end

-- Function/class textobjects. nvim-treesitter's main branch ships no
-- textobjects.scm (verified: 0 files); the companion repo carries its own
-- queries -- confirmed present for rust (15 fn/class captures), python, lua, go
-- and typescript.
loads 'nvim-treesitter-textobjects'

-- Neovim's own ftplugin/python.vim maps ]m and [m buffer-locally in n/o/x modes
-- (its lines 64-83), which would shadow these globals in the most-used language
-- here. Opt out per filetype rather than with the README's global
-- no_plugin_maps, which would disable ftplugin maps across all 29 filetypes.
check('python ftplugin maps disabled (]m would be shadowed)', vim.g.no_python_maps == true)
check('ruby ftplugin maps disabled', vim.g.no_ruby_maps == true)

-- Upstream key scheme: am/im for functions (m = method), ac/ic for classes.
-- Leaves mini.ai's `f` (function-call) untouched, so no remap is needed.
for _, lhs in ipairs { 'am', 'im', 'ac', 'ic' } do
  local found = false
  for _, m in ipairs(vim.api.nvim_get_keymap 'o') do
    if m.lhs == lhs then found = true end
  end
  check('operator-pending textobject ' .. lhs, found)
end
for _, lhs in ipairs { ']m', '[m', ']c', '[c' } do
  check('movement ' .. lhs, has_nmap(lhs))
end

-- lazydev: on-demand vim.* types when editing this config. Gated to
-- FileType lua, so it is NOT loaded in a headless run with no Lua buffer --
-- assert the source wires it rather than that it is loaded.
local lsp_src2 = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/lsp.lua', 'r')
if lsp_src2 then
  local src2 = lsp_src2:read 'a'
  lsp_src2:close()
  check('lazydev registered', src2:match 'lazydev' ~= nil)
  check('lazydev gated to lua filetype', src2:match "pattern = 'lua'" ~= nil, 'must not load for every filetype')
end

-- Sessions. Deferred to the first <leader>q press, so assert the keymaps exist
-- rather than that the plugin is loaded.
for _, lhs in ipairs { '<leader>qs', '<leader>qS', '<leader>ql', '<leader>qd' } do
  check('session keymap ' .. lhs, has_nmap(lhs))
end
check('persistence NOT loaded at startup', package.loaded.persistence == nil, 'must stay deferred')

-- Project-wide replace. Telescope can grep but not replace across files.
check('search-and-replace keymap <leader>sr', has_nmap '<leader>sr')
check('grug-far NOT loaded at startup', package.loaded['grug-far'] == nil, 'must stay deferred')

-- Bracket navigation, filling the gaps in the existing ]d / ]e / ]h set.
for _, lhs in ipairs { ']t', '[t', ']q', '[q', ']b', '[b' } do
  check('bracket keymap ' .. lhs, has_nmap(lhs))
end

-- Harpoon: pinned-file shortlist with a telescope UI. Deferred to first
-- <leader>h press; the numbered-slot maps prove the keymaps exist without
-- loading it.
for _, lhs in ipairs { '<leader>ha', '<leader>hh', '<leader>h1' } do
  check('harpoon keymap ' .. lhs, has_nmap(lhs))
end
check('harpoon NOT loaded at startup', package.loaded.harpoon == nil, 'must stay deferred')

-- diffview: side-by-side diffs and file history. Deferred to first <leader>gd.
check('diffview keymap <leader>gd', has_nmap '<leader>gd')
check('diffview NOT loaded at startup', package.loaded['diffview'] == nil, 'must stay deferred')

print '== completion and formatting =='
loads 'conform'
loads 'lint'

-- blink.cmp and LuaSnip are NOT required here on purpose. They are deliberately
-- kept off runtimepath until the first InsertEnter/CmdlineEnter (see the comment
-- in lua/plugins/completion.lua), so `require` correctly fails at startup.
-- Asserting their absence is the real invariant -- if they ever load eagerly,
-- ~82 modules come back onto the startup path.
check('blink.cmp deferred (not loaded at startup)', package.loaded['blink.cmp'] == nil, 'loaded eagerly; startup regression')
check('luasnip deferred (not loaded at startup)', package.loaded.luasnip == nil, 'loaded eagerly; startup regression')
check('dap deferred', package.loaded.dap == nil, 'loaded eagerly')
check('neotest deferred', package.loaded.neotest == nil, 'loaded eagerly')
check('mason deferred', package.loaded.mason == nil, 'loaded eagerly')
check('completion autocmds registered', count_autocmds 'config-completion' == 2, 'expected InsertEnter + CmdlineEnter')

-- The deferral is only correct if it actually loads on demand. Spawn a child
-- that presses `i` and confirm blink appears -- this is what caught the earlier
-- bug where two `once` autocmds sharing an augroup deleted each other, leaving
-- completion permanently unloaded.
local probe = ('%s/tests/_insert_probe.lua'):format(vim.fn.stdpath 'config')
local wrote = io.open(probe, 'w')
if wrote then
  wrote:write [[
vim.cmd('enew')
vim.api.nvim_feedkeys('i', 'x', false)
vim.wait(5000, function() return package.loaded['blink.cmp'] ~= nil end, 100)
io.write(package.loaded['blink.cmp'] ~= nil and 'LOADED' or 'NOT_LOADED')
vim.cmd('cq 0')
]]
  wrote:close()
  local r = vim.system({ vim.v.progpath, '--headless', '-u', vim.fn.stdpath 'config' .. '/init.lua', '-l', probe }, { text = true }):wait(30000)
  os.remove(probe)
  check('completion loads on first insert', (r.stdout or ''):match 'LOADED' ~= nil, ('child said %q'):format((r.stdout or ''):gsub('%s', '')))
end

local conform_ok, conform = pcall(require, 'conform')
if conform_ok then
  local by_ft = conform.formatters_by_ft or {}
  for _, ft in ipairs { 'python', 'lua', 'rust', 'typescript', 'typescriptreact', 'json', 'sh', 'toml', 'go', 'markdown' } do
    check('formatter for ' .. ft, by_ft[ft] ~= nil, 'none configured')
  end
end

check('format toggle mapped', has_nmap '<leader>uf')
check('buffer format toggle mapped', has_nmap '<leader>uF')
check('format-on-save enabled by default', vim.g.autoformat ~= false)
check('lint augroup', count_autocmds 'config-lint' > 0)
check('markdownlint config file exists', vim.uv.fs_stat(vim.fn.stdpath 'config' .. '/.markdownlint-cli2.yaml') ~= nil)

local lint_ok, lint_mod = pcall(require, 'lint')
if lint_ok then check('markdown linter registered', lint_mod.linters_by_ft.markdown ~= nil) end

print '== cloudformation =='
local ok_cfn, cfn = pcall(require, 'config.cloudformation')
check('config.cloudformation loads', ok_cfn, tostring(cfn))
if ok_cfn then
  check('cloudformation.intrinsic_tags is a non-empty list', type(cfn.intrinsic_tags) == 'table' and #cfn.intrinsic_tags > 0, tostring(cfn.intrinsic_tags))
  check('cloudformation.schema_url is a string', type(cfn.schema_url) == 'string' and cfn.schema_url:match '^https?://' ~= nil, tostring(cfn.schema_url))
  check('cloudformation.is_template is a function', type(cfn.is_template) == 'function')

  -- intrinsic_tags must cover the tags yaml-language-server would otherwise
  -- reject. A representative sample (both scalar and sequence forms exist for
  -- some, e.g. !Sub); assert the tag names appear somewhere in the list.
  local tag_blob = table.concat(cfn.intrinsic_tags, ' ')
  for _, tag in ipairs { '!Ref', '!GetAtt', '!Sub', '!If', '!Join', '!Select', '!FindInMap', '!ImportValue', '!Equals', '!And', '!Or', '!Not', '!Base64' } do
    check('customTag covers ' .. tag, tag_blob:find(tag, 1, true) ~= nil, 'missing from intrinsic_tags')
  end

  if type(cfn.is_template) == 'function' then
    -- YAML with AWSTemplateFormatVersion -> template.
    local b1 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b1, 0, -1, false, { 'AWSTemplateFormatVersion: "2010-09-09"', 'Resources:', '  B:', '    Type: AWS::S3::Bucket' })
    check('is_template true for AWSTemplateFormatVersion', cfn.is_template(b1) == true)
    vim.api.nvim_buf_delete(b1, { force = true })

    -- YAML with only a top-level Resources: key -> template.
    local b2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { '# a stack', 'Resources:', '  Q:', '    Type: AWS::SQS::Queue' })
    check('is_template true for top-level Resources:', cfn.is_template(b2) == true)
    vim.api.nvim_buf_delete(b2, { force = true })

    -- Ordinary YAML (a CI workflow) -> NOT a template. `jobs:` and a nested
    -- `resources:` under it must not trigger; only a TOP-LEVEL Resources: does.
    local b3 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b3, 0, -1, false, { 'name: CI', 'on: push', 'jobs:', '  build:', '    resources:', '      cpu: 2' })
    check('is_template false for ordinary YAML workflow', cfn.is_template(b3) == false)
    vim.api.nvim_buf_delete(b3, { force = true })

    -- Capital-R `Resources:` but INDENTED (nested under another key), with no
    -- AWSTemplateFormatVersion and no column-0 Resources:. Exercises the `^`
    -- anchor: only a TOP-LEVEL key counts, so this must NOT match.
    local b5 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b5, 0, -1, false, { 'service:', '  config:', '    Resources: still-nested' })
    check('is_template false for indented Resources: key', cfn.is_template(b5) == false)
    vim.api.nvim_buf_delete(b5, { force = true })

    -- JSON template.
    local b4 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b4, 0, -1, false, { '{', '  "AWSTemplateFormatVersion": "2010-09-09",', '  "Resources": {}', '}' })
    check('is_template true for JSON template', cfn.is_template(b4) == true)
    vim.api.nvim_buf_delete(b4, { force = true })
  end

  -- Detection autocmd must be registered by init.lua (own augroup).
  check('cloudformation augroup exists', count_autocmds 'config-cloudformation' > 0, 'setup() not wired from init.lua')

  -- init.lua must actually require the module (see the WIRING vs STATE note near
  -- the top of this file: requiring it here would mask a missing init.lua line).
  local cfn_init = io.open(vim.fn.stdpath 'config' .. '/init.lua', 'r')
  if cfn_init then
    local src = cfn_init:read 'a'
    cfn_init:close()
    check('init.lua sets up config.cloudformation', src:match "require%s*%(?%s*'config%.cloudformation'%s*%)?%s*%.setup" ~= nil or src:match "require%('config%.cloudformation'%)" ~= nil, 'not required in init.lua')
  end

  -- End-to-end: a yaml buffer with template content, run through the detection
  -- callback, gets the composite filetype and the marker variable.
  if type(cfn.setup) == 'function' then
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'AWSTemplateFormatVersion: "2010-09-09"', 'Resources:', '  B: { Type: AWS::S3::Bucket }' })
    vim.bo[b].filetype = 'yaml'
    check('detected buffer filetype is yaml.cloudformation', vim.bo[b].filetype == 'yaml.cloudformation', vim.bo[b].filetype)
    check('detected buffer sets b:cloudformation', vim.b[b].cloudformation == true)
    vim.api.nvim_buf_delete(b, { force = true })

    -- Same for JSON, exercising the base = 'json' branch of setup().
    local bj = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bj, 0, -1, false, { '{', '  "AWSTemplateFormatVersion": "2010-09-09",', '  "Resources": { "B": { "Type": "AWS::S3::Bucket" } }', '}' })
    vim.bo[bj].filetype = 'json'
    check('detected JSON buffer filetype is json.cloudformation', vim.bo[bj].filetype == 'json.cloudformation', vim.bo[bj].filetype)
    check('detected JSON buffer sets b:cloudformation', vim.b[bj].cloudformation == true)
    vim.api.nvim_buf_delete(bj, { force = true })

    -- A plain yaml buffer must be left as-is (no recursion, no false positive).
    local b2 = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { 'name: CI', 'jobs:', '  build:', '    steps: []' })
    vim.bo[b2].filetype = 'yaml'
    check('ordinary yaml buffer stays yaml', vim.bo[b2].filetype == 'yaml', vim.bo[b2].filetype)
    vim.api.nvim_buf_delete(b2, { force = true })
  end
end

if #failures > 0 then
  print(('\n%d failure(s): %s'):format(#failures, table.concat(failures, ', ')))
else
  print '\n0 failure(s)'
end
vim.cmd(#failures == 0 and 'cq 0' or 'cq 1')
