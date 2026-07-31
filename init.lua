-- Fast modular Neovim config. See docs/superpowers/specs/ for design rationale.
-- Requires Neovim 0.12+ (uses vim.pack).

-- Proves to tests/health.lua that this file started executing. Paired with
-- config_loaded on the last line, so the harness can tell "never ran" apart from
-- "errored partway". Both are load-bearing; see tests/health.lua.
vim.g.config_sentinel = true

-- Cache compiled Lua modules. Must precede the first require of a config module.
vim.loader.enable()

-- Leader must be set before any plugin or keymap is defined.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- FiraCode Nerd Font is configured in both wezterm and iTerm2.
vim.g.have_nerd_font = true

-- nvim-tree requires netrw be disabled, and it must happen before netrw's own
-- plugin files load. Also saves ~3.5ms of startup (netrwPlugin.vim + matchit).
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Some plugins need a build step after install or update. vim.pack emits
-- PackChanged for this; see :help vim.pack-events. Registered BEFORE the first
-- vim.pack.add so install-time hooks fire.
local function run_build(name, cmd, cwd)
  local result = vim.system(cmd, { cwd = cwd }):wait()
  if result.code ~= 0 then
    local output = (result.stderr ~= '' and result.stderr) or result.stdout or 'no output'
    vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_autocmd('PackChanged', {
  desc = 'Run plugin build steps',
  callback = function(ev)
    local kind, name, path = ev.data.kind, ev.data.spec.name, ev.data.path
    if kind ~= 'install' and kind ~= 'update' then return end

    if name == 'LuaSnip' and vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then
      run_build(name, { 'make', 'install_jsregexp' }, path)
    elseif name == 'telescope-fzf-native.nvim' and vim.fn.executable 'make' == 1 then
      -- The native C sorter; without it telescope falls back to a slower Lua one.
      run_build(name, { 'make' }, path)
    elseif name == 'nvim-treesitter' then
      if not ev.data.active then vim.cmd.packadd 'nvim-treesitter' end
      vim.cmd 'TSUpdate'
    end
  end,
})

--- Shorthand for GitHub plugin sources.
---@param repo string "owner/name"
---@return string
_G.gh = function(repo) return 'https://github.com/' .. repo end

require 'config.options'
require 'config.keymaps'
require 'config.autocmds'
require 'config.diagnostics'

-- Required for its side-effect-free data by lua/plugins/lsp.lua; required here
-- so a load error surfaces at startup rather than on first LSP attach.
require 'config.project'

require 'plugins.ui'
require 'plugins.editor'
require 'plugins.treesitter'
require 'plugins.picker' -- must precede lsp: LspAttach keymaps require telescope
require 'plugins.lsp'
require 'plugins.explorer'
require 'plugins.completion'
require 'plugins.format'
require 'plugins.git'
require 'plugins.rust'
require 'plugins.dap'
require 'plugins.test'

-- MUST stay last. Signals that every require above completed; tests/health.lua
-- treats its absence as "init.lua errored partway". Append new requires ABOVE.
vim.g.config_loaded = true
