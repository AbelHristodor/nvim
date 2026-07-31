-- Quality-of-life editor plugins: big-file guard, autopairing, indent guides,
-- sessions and project-wide replace.
--
-- Kept separate from lua/plugins/ui.lua, which owns appearance (colorscheme,
-- statusline, icons). This file owns behaviour.

-- snacks.nvim -- THE ONE NEW EAGER PLUGIN, and it cannot be deferred.
--
-- `bigfile` has to be registered before the BufReadPre that opens the file it is
-- meant to guard, and `quickfile` exists specifically to render a buffer BEFORE
-- plugins load. Deferring either defeats its purpose.
--
-- Affordable because Snacks.setup() only registers autocmds: it builds one
-- `snacks` augroup with a single `once` autocmd covering every event it cares
-- about (its init.lua:185-193), and each submodule is required from that callback
-- via an __index metatable. So bigfile arrives on BufReadPre, quickfile on
-- BufReadPost, input on UIEnter -- none at startup.
--
-- Verified rather than assumed: after a real startup `package.loaded` holds
-- exactly ONE snacks module (`snacks` itself), not four. Self-time for
-- require('plugins.editor'), 3 runs: 1.48 / 1.46 / 1.62 ms, plus 0.11-0.26 ms to
-- source snacks' own plugin/snacks.lua. A/B on the require line, median of 7
-- real startups: 98.7 ms without, 102.0 ms with.
--
-- Scope is deliberately four modules. Rejected: picker and explorer (duplicate
-- telescope and nvim-tree), statuscolumn and dashboard (cosmetic), scroll and
-- words (per-motion and per-CursorHold work; `words` duplicates the
-- documentHighlight autocmd in lua/plugins/lsp.lua), and indent (mini.indentscope
-- owns guides -- enabling both draws overlapping extmarks and flickers).
vim.pack.add { gh 'folke/snacks.nvim' }

require('snacks').setup {
  -- Stops treesitter and the LSP attaching to generated or minified files.
  -- This config had no large-file guard at all before.
  bigfile = { enabled = true },

  -- Renders the file before plugins finish loading, for `nvim <file>`.
  quickfile = { enabled = true },

  -- Replaces vim.notify (its init.lua:219-223 installs a one-shot trampoline
  -- that swaps itself for Snacks.notifier.notify on the first call). The 12
  -- existing call sites (VenvSelect, the format toggles, lazygit, the
  -- PackChanged build hook) become stacked auto-dismissing popups instead of
  -- :messages lines you have to go looking for.
  notifier = { enabled = true, timeout = 3000 },

  -- Replaces vim.ui.input. No conflict with the telescope ui-select extension
  -- in lua/plugins/picker.lua: vim.ui.input and vim.ui.select are separate hooks.
  input = { enabled = true },
}

vim.keymap.set('n', '<leader>n', function() require('snacks').notifier.show_history() end, { desc = 'Notification history' })
vim.keymap.set('n', '<leader>un', function() require('snacks').notifier.hide() end, { desc = 'Dismiss notifications' })
