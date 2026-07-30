-- Fast modular Neovim config. See docs/superpowers/specs/ for design rationale.
-- Requires Neovim 0.12+ (uses vim.pack).

-- Proves to tests/health.lua that this file actually executed. See the harness
-- self-check note in the plan's testing section.
vim.g.config_sentinel = true

-- Cache compiled Lua modules. Must be first.
vim.loader.enable()

-- Leader must be set before any plugin or keymap is defined.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- FiraCode Nerd Font is configured in both wezterm and iTerm2.
vim.g.have_nerd_font = true

require 'config.options'
