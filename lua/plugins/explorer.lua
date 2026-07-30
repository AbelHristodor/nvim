-- oil.nvim: edit the filesystem as a normal buffer.
--
-- fzf-lua has no tree view, so this fills that gap. oil is a
-- single-directory, vinegar-style explorer rather than a persistent sidebar
-- tree: you edit the buffer (rename lines, delete lines, add lines) and `:w`
-- applies the filesystem changes. Its README warns against lazy-loading it,
-- so it is loaded eagerly.

vim.pack.add { gh 'stevearc/oil.nvim' }

require('oil').setup {
  default_file_explorer = true,
  columns = { 'icon' },
  view_options = {
    show_hidden = true,
    is_hidden_file = function(name) return name == '..' or name == '.git' end,
  },
  keymaps = {
    ['<C-h>'] = false, -- keep window navigation
    ['<C-l>'] = false,
    ['q'] = 'actions.close',
  },
  float = { padding = 4, max_width = 120, max_height = 40 },
}

vim.keymap.set('n', '<leader>e', '<cmd>Oil --float<CR>', { desc = 'File explorer (float)' })
vim.keymap.set('n', '-', '<cmd>Oil<CR>', { desc = 'Open parent directory' })
