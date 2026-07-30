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

require 'config.options'

-- MUST stay last. Signals that every require above completed; tests/health.lua
-- treats its absence as "init.lua errored partway". Append new requires ABOVE.
vim.g.config_loaded = true
