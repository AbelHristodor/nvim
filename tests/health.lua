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

print('== environment ==')
-- has('nvim-0.12') rather than vim.version.ge(): semver ranks a prerelease
-- below its release, so ge(0.12.0-dev, 0.12) is false on nightly builds even
-- though they have the 0.12 APIs this config needs. Verified.
check('neovim >= 0.12', vim.fn.has 'nvim-0.12' == 1, tostring(vim.version()))
check('vim.pack available', type(vim.pack) == 'table' and type(vim.pack.add) == 'function',
  ('vim.pack=%s add=%s'):format(type(vim.pack), type(vim.pack) == 'table' and type(vim.pack.add) or 'n/a'))
check('vim.lsp.config available', type(vim.lsp.config) == 'table' or type(vim.lsp.config) == 'function',
  ('type=%s'):format(type(vim.lsp.config)))
check('running under nvim-dev', vim.fn.stdpath('config'):match('nvim%-dev') ~= nil, vim.fn.stdpath 'config')

-- HARNESS SELF-CHECK. `nvim -l` skips user config unless -u is given, so
-- without it init.lua never runs and every check below would pass or fail for
-- the wrong reason. `vim.g.config_sentinel` is set by the first line of the new
-- init.lua (Task 2); its absence means the suite is testing nothing.
--
-- Expect this to fail until Task 2 replaces init.lua. That is the intended red
-- state, not a broken harness.
check('init.lua ran (harness wired correctly)', vim.g.config_sentinel == true, 'sentinel missing -- run via tests/run.sh, or init.lua not yet rewritten (Task 2)')

print('== modules load ==')
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

print('== options ==')
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
-- (nvim_get_option_info2 reports was_set=false, last_set_sid=0), while the same
-- config at normal startup yields 200. So an in-process check here would be
-- permanently unsatisfiable -- a test that can never go green.
--
-- updatetime is the ONLY option this suite asserts that -l overrides; the other
-- eight above survive intact (verified individually). It matters because it
-- drives CursorHold, which gates LSP document highlighting.
local ut = vim.system({
  'nvim', '--headless', '-u', vim.fn.stdpath 'config' .. '/init.lua',
  '-c', 'lua io.write(vim.o.updatetime)', '-c', 'qa',
}, { text = true }):wait()
check('updatetime 200 (measured at real startup)', (ut.stdout or ''):match '200' ~= nil,
  ('child reported %q, code %d'):format((ut.stdout or ''):gsub('%s', ''), ut.code))

if #failures > 0 then
  print(('\n%d failure(s): %s'):format(#failures, table.concat(failures, ', ')))
else
  print '\n0 failure(s)'
end
vim.cmd(#failures == 0 and 'cq 0' or 'cq 1')
