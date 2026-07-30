-- nvim-tree: sidebar file tree.
--
-- Chosen over oil.nvim (buffer-as-filesystem) because a persistent sidebar is
-- what was wanted, and over neo-tree/snacks-explorer because nvim-tree is the
-- most widely used standalone tree.
--
-- DEFERRED. A tree is only needed once you ask for it, so the plugin is not
-- registered at startup at all -- see the note in lua/plugins/completion.lua for
-- why `{ load = false }` is insufficient. The keymaps below load it on first use.
--
-- netrw is disabled in init.lua, as nvim-tree requires.

local tree_specs = { gh 'nvim-tree/nvim-tree.lua' }

local tree_ready = false

local function setup_tree()
  if tree_ready then return end
  tree_ready = true

  vim.pack.add(tree_specs)

  require('nvim-tree').setup {
    hijack_cursor = true, -- keep the cursor on the filename, not column 0
    sync_root_with_cwd = true,
    respect_buf_cwd = true,
    update_focused_file = { enable = true, update_root = false },

    view = {
      width = 34,
      signcolumn = 'yes',
      preserve_window_proportions = true,
    },

    renderer = {
      group_empty = true, -- collapse a/b/c chains into one line
      highlight_git = true,
      indent_markers = { enable = true },
      icons = { git_placement = 'right_align' },
    },

    -- Hide build output and caches, matching the language-server excludes in
    -- lua/config/project.lua.
    filters = {
      dotfiles = false,
      git_ignored = false,
      custom = { '^\\.git$', '^__pycache__$', '^\\.mypy_cache$', '^\\.pytest_cache$', '^\\.ruff_cache$', '^node_modules$', '^target$' },
    },

    git = { enable = true, ignore = false },
    diagnostics = { enable = true, show_on_dirs = true },

    actions = {
      open_file = { quit_on_open = false, resize_window = true },
    },

    on_attach = function(buf)
      local api = require 'nvim-tree.api'
      -- Start from the defaults so every documented mapping still works, then
      -- adjust only what conflicts with this config.
      api.config.mappings.default_on_attach(buf)

      local function map(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { buffer = buf, desc = 'nvim-tree: ' .. desc, nowait = true }) end

      -- nvim-tree binds <C-k> to show file info, which would shadow the
      -- window-navigation maps from lua/config/keymaps.lua inside the tree.
      vim.keymap.set('n', '<C-k>', '<C-w>k', { buffer = buf, desc = 'Go to upper window' })
      map('i', api.node.show_info_popup, 'Info')

      map('l', api.node.open.edit, 'Open')
      map('h', api.node.navigate.parent_close, 'Close directory')
      map('<Esc>', api.tree.close, 'Close tree')
    end,
  }
end

local map = vim.keymap.set

--- Wraps a tree action so the first invocation loads the plugin first.
---@param fn fun(api: table)
---@return fun()
local function lazy_tree(fn)
  return function()
    setup_tree()
    fn(require 'nvim-tree.api')
  end
end

-- <leader>e / <leader>E match LazyVim's explorer bindings (root dir / cwd).
map('n', '<leader>e', lazy_tree(function(api) api.tree.toggle { find_file = true, focus = true } end), { desc = 'Explorer (Root Dir)' })
map('n', '<leader>E', lazy_tree(function(api) api.tree.toggle { find_file = true, focus = true, update_root = true } end), { desc = 'Explorer (cwd)' })
map('n', '<leader>fe', lazy_tree(function(api) api.tree.toggle { find_file = true, focus = true } end), { desc = 'Explorer (Root Dir)' })
map('n', '<leader>fE', lazy_tree(function(api) api.tree.toggle { find_file = true, focus = true, update_root = true } end), { desc = 'Explorer (cwd)' })
