-- blink.cmp: completion engine.
--
-- Chosen over nvim-cmp: it is faster, has fewer moving parts, and is where
-- momentum is. Pinned to major 1 for stability.

-- DEFERRED, and the deferral needs explaining because the obvious version does
-- not work.
--
-- Completion is unreachable until insert mode, so none of this belongs on the
-- startup path. But `{ load = false }` alone is not enough: blink ships
-- `plugin/blink-cmp.lua`, which Neovim's own "loading rtp plugins" phase sources
-- anyway, and that file calls `require('blink.cmp')` to register LSP
-- capabilities -- pulling in blink AND LuaSnip's ~52 modules. Measured: 178
-- startup requires with completion vs 94 without, ~142ms vs ~82ms.
--
-- `{ load = false }` is NOT sufficient here, and the reason is worth recording.
-- It defers sourcing at `vim.pack.add` time, but the plugin is still placed on
-- runtimepath, so Neovim sources `plugin/blink-cmp.lua` later in the same
-- startup anyway. Measured ordering:
--   119ms  init.lua finishes
--   135ms  blink.cmp/plugin/blink-cmp.lua sourced   <-- still on the startup path
--   152ms  "loading rtp plugins"
-- That file calls require('blink.cmp') at line 5, which drags in blink's ~23
-- modules and LuaSnip's ~59.
--
-- So the deferral has to keep the plugins OFF runtimepath until first use: no
-- vim.pack.add at startup at all. `vim.pack.add` is called inside
-- setup_completion(), on the first InsertEnter/CmdlineEnter. It is idempotent
-- (":help vim.pack.add" -- adding a plugin twice in one session does nothing),
-- and install-on-first-use is fine because the plugins are already on disk after
-- the initial run.
--
-- Trade-off accepted: on a genuinely fresh machine the very first insert pays
-- the clone. Everything after that is instant.
local completion_specs = {
  { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' },
  gh 'rafamadriz/friendly-snippets',
  { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' },
}

local completion_ready = false

local function setup_completion()
  if completion_ready then return end
  completion_ready = true

  -- Registers on runtimepath and sources plugin/ now, at first use.
  vim.pack.add(completion_specs)

  -- LuaSnip pulls in ~52 modules, so it is loaded here (on first insert) rather
  -- than at startup. from_vscode.lazy_load() only registers friendly-snippets'
  -- directories; the snippet files themselves are read per filetype on demand.
  require('luasnip').setup {}
  require('luasnip.loaders.from_vscode').lazy_load()

  require('blink.cmp').setup {
    -- 'default' mirrors built-in ins-completion: <C-y> accepts, <C-n>/<C-p>
    -- cycle, <C-space> opens docs.
    keymap = { preset = 'default' },

    appearance = { nerd_font_variant = 'mono' },

    completion = {
      documentation = { auto_show = true, auto_show_delay_ms = 200 },
      ghost_text = { enabled = false },
      menu = { draw = { treesitter = { 'lsp' } } },
    },

    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer' },
    },

    snippets = { preset = 'luasnip' },

    -- The Rust matcher downloads a prebuilt binary and is substantially faster
    -- than the Lua implementation; fall back with a warning if unavailable.
    fuzzy = { implementation = 'prefer_rust_with_warning' },

    signature = { enabled = true },
  }
end

-- Load on the first insert. Guarded by `completion_ready` rather than by
-- `once = true`:
--
-- An earlier version used `once` on two autocmds sharing one augroup. That is a
-- trap -- `once` deletes the autocmd after firing, and because Neovim's -c
-- startup commands fire CmdlineEnter immediately, the CmdlineEnter handler ran
-- during startup and took the InsertEnter handler down with it. The group ended
-- up empty and completion never loaded at all. Verified: the augroup reported 0
-- autocmds and blink stayed unloaded after a real keystroke.
--
-- A plain flag is simpler and cannot be defeated by event ordering.
local completion_group = vim.api.nvim_create_augroup('config-completion', { clear = true })

vim.api.nvim_create_autocmd('InsertEnter', {
  desc = 'Load completion on first insert',
  group = completion_group,
  callback = setup_completion,
})

-- Command-line completion also needs blink, and InsertEnter does not fire for
-- `:`. Deliberately NOT `once`, and the handler self-guards.
vim.api.nvim_create_autocmd('CmdlineEnter', {
  desc = 'Load completion on first cmdline',
  group = completion_group,
  callback = setup_completion,
})
