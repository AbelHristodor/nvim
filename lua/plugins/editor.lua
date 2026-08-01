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
-- Scope is deliberately six modules. Rejected: picker and explorer (duplicate
-- telescope and nvim-tree), statuscolumn and dashboard (cosmetic), scroll
-- (per-motion work), and scope/indent (mini.indentscope owns guides -- enabling
-- both draws overlapping extmarks and flickers).
--
-- Both extra modules defer their cost: `gitbrowse` is required only when its
-- keymap fires, and `words` loads on LspAttach (its events table keys it there),
-- so neither touches the startup path.
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

  -- Auto-highlights other references to the symbol under the cursor and gives
  -- ]] / [[ to jump between them. REPLACES the manual documentHighlight autocmd
  -- that used to live in lua/plugins/lsp.lua: this module registers its own
  -- CursorMoved/ModeChanged highlight handlers on LspAttach, so running both
  -- would double-highlight. Debounced 200ms, same as the old autocmd's implicit
  -- CursorHold delay.
  words = { enabled = true },

  -- Opens the current line (or visual range) on the git remote's web UI.
  -- <leader>gB below.
  gitbrowse = { enabled = true },
}

vim.keymap.set('n', '<leader>n', function() require('snacks').notifier.show_history() end, { desc = 'Notification history' })
vim.keymap.set('n', '<leader>un', function() require('snacks').notifier.hide() end, { desc = 'Dismiss notifications' })

-- Open current line / selection on the git remote (GitHub, etc.).
vim.keymap.set({ 'n', 'x' }, '<leader>gB', function() require('snacks').gitbrowse() end, { desc = 'Git Browse (open)' })

-- Navigate LSP references to the symbol under the cursor. These override the
-- default ]] / [[ section motions, matching the LazyVim convention.
vim.keymap.set({ 'n', 't' }, ']]', function() require('snacks').words.jump(vim.v.count1) end, { desc = 'Next reference' })
vim.keymap.set({ 'n', 't' }, '[[', function() require('snacks').words.jump(-vim.v.count1) end, { desc = 'Prev reference' })

-- persistence.nvim: session management.
--
-- Chosen over mini.sessions (which is already on disk) because it matches
-- LazyVim's <leader>q* keymaps, preserving the muscle memory this config mirrors
-- everywhere else, and because it autosaves on VimLeavePre rather than needing a
-- manual save.
--
-- DEFERRED to the first <leader>q press, for the reason in
-- lua/plugins/completion.lua.
--
-- KNOWN TRADE-OFF: persistence.setup() calls start() internally, which is what
-- registers the VimLeavePre autosave. Because setup runs lazily, a session is
-- only written if you touched a session keymap during that Neovim run. Making
-- autosave unconditional would mean loading it eagerly; that is the cost this
-- config is not willing to pay for a feature used at session boundaries.
local persistence_specs = { gh 'folke/persistence.nvim' }
local persistence_ready = false

local function setup_persistence()
  if persistence_ready then return end
  persistence_ready = true

  vim.pack.add(persistence_specs)
  require('persistence').setup {}
end

---Wraps a persistence action so the first invocation loads the plugin.
---@param fn fun(p: table)
---@return fun()
local function lazy_session(fn)
  return function()
    setup_persistence()
    fn(require 'persistence')
  end
end

vim.keymap.set('n', '<leader>qs', lazy_session(function(p) p.load() end), { desc = 'Restore session' })
vim.keymap.set('n', '<leader>qS', lazy_session(function(p) p.select() end), { desc = 'Select session' })
vim.keymap.set('n', '<leader>ql', lazy_session(function(p) p.load { last = true } end), { desc = 'Restore last session' })
vim.keymap.set('n', '<leader>qd', lazy_session(function(p) p.stop() end), { desc = "Don't save current session" })

-- grug-far.nvim: project-wide find and replace.
--
-- Telescope covers grep but has no multi-file replace. <leader>sr matches
-- LazyVim. Deferred to first use, as everywhere else in this config.
local grug_specs = { gh 'MagicDuck/grug-far.nvim' }
local grug_ready = false

vim.keymap.set('n', '<leader>sr', function()
  if not grug_ready then
    grug_ready = true
    vim.pack.add(grug_specs)
    require('grug-far').setup { headerMaxWidth = 80 }
  end
  require('grug-far').open()
end, { desc = 'Search and Replace' })
