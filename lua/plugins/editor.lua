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
-- Affordable because Snacks.setup() mostly just registers autocmds: it builds one
-- `snacks` augroup with a single `once` autocmd covering every event it cares
-- about (its init.lua:185-193), and each submodule is required from that callback
-- via an __index metatable.
--
-- But only SOME of it is deferred, and the split is not what it looks like.
-- snacks keys its submodules by event, and `input` sits in the UIEnter group
-- (its init.lua:161: `UIEnter = { "dashboard", "scroll", "input", "scope",
-- "picker" }`). In a TUI, UIEnter fires DURING startup -- so at real startup
-- `package.loaded` holds THREE snacks modules, not one:
--     snacks, snacks.util, snacks.input
-- (`snacks.util` comes along because input.lua:31 calls Snacks.util.set_hl.)
-- Genuinely deferred: only `bigfile` (BufReadPre) and `quickfile` (BufReadPost),
-- which need a buffer that startup does not have.
--
-- Do NOT re-measure this headlessly. `--headless` never fires UIEnter, so it
-- reports one module and hides the other two; that mistake was made twice while
-- writing this file. Measured instead with a child `nvim --embed` WITHOUT
-- --headless, which blocks startup until nvim_ui_attach and so reproduces the
-- real UIEnter-within-startup ordering. Its --startuptime trace:
--     105.752  000.763  require('snacks.util')
--     106.019  000.909  require('snacks.input')
-- both landing before `--- NVIM STARTED ---` at ~116 ms.
--
-- Marginal cost, A/B on this file's require line, two rounds of 7 and 9
-- UI-attached runs: medians 116.5 vs 111.4 and 115.7 vs 109.3 ms -- so roughly
-- 5-6 ms. Stated as a range on purpose: per-run spread was 99-126 ms, WIDER than
-- the delta itself, so the median difference is directional, not precise. It is
-- consistent with the summed self-times above (~1.5 ms for this file, ~0.2 ms to
-- source snacks' plugin/, ~1.7 ms for util+input).
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
