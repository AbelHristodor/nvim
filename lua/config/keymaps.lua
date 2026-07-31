-- Non-plugin keymaps. LSP keymaps live in lua/plugins/lsp.lua (buffer-local
-- on LspAttach); picker keymaps live in lua/plugins/picker.lua.
--
-- Scheme follows LazyVim conventions to preserve existing muscle memory.

local map = vim.keymap.set

-- Clear search highlight.
map('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })

-- Window navigation.
map('n', '<C-h>', '<C-w>h', { desc = 'Go to left window' })
map('n', '<C-j>', '<C-w>j', { desc = 'Go to lower window' })
map('n', '<C-k>', '<C-w>k', { desc = 'Go to upper window' })
map('n', '<C-l>', '<C-w>l', { desc = 'Go to right window' })

-- Window resizing.
map('n', '<C-Up>', '<cmd>resize +2<CR>', { desc = 'Increase window height' })
map('n', '<C-Down>', '<cmd>resize -2<CR>', { desc = 'Decrease window height' })
map('n', '<C-Left>', '<cmd>vertical resize -2<CR>', { desc = 'Decrease window width' })
map('n', '<C-Right>', '<cmd>vertical resize +2<CR>', { desc = 'Increase window width' })

-- Buffers.
map('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
map('n', '<S-l>', '<cmd>bnext<CR>', { desc = 'Next buffer' })
map('n', '<leader>bd', '<cmd>bdelete<CR>', { desc = 'Delete buffer' })
map('n', '<leader>bo', function()
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted and not vim.bo[buf].modified then vim.api.nvim_buf_delete(buf, {}) end
  end
end, { desc = 'Delete other buffers' })

-- Move lines, keeping selection.
map('n', '<A-j>', '<cmd>m .+1<CR>==', { desc = 'Move line down' })
map('n', '<A-k>', '<cmd>m .-2<CR>==', { desc = 'Move line up' })
map('v', '<A-j>', ":m '>+1<CR>gv=gv", { desc = 'Move selection down' })
map('v', '<A-k>', ":m '<-2<CR>gv=gv", { desc = 'Move selection up' })

-- Keep the cursor centred when jumping half-pages and through search results.
map('n', '<C-d>', '<C-d>zz', { desc = 'Half page down (centred)' })
map('n', '<C-u>', '<C-u>zz', { desc = 'Half page up (centred)' })
map('n', 'n', 'nzzzv', { desc = 'Next search result (centred)' })
map('n', 'N', 'Nzzzv', { desc = 'Previous search result (centred)' })

-- Indent without losing the visual selection.
map('v', '<', '<gv', { desc = 'Indent left' })
map('v', '>', '>gv', { desc = 'Indent right' })

-- Save.
map({ 'i', 'x', 'n', 's' }, '<C-s>', '<cmd>w<CR><Esc>', { desc = 'Save file' })

-- Terminal: escape to normal mode.
map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Quickfix / location list.
map('n', '<leader>xq', '<cmd>copen<CR>', { desc = 'Quickfix list' })
map('n', '<leader>xl', '<cmd>lopen<CR>', { desc = 'Location list' })

-- Bracket navigation, completing the ]d / ]e / ]h set defined elsewhere
-- (diagnostics in lua/config/diagnostics.lua, git hunks in lua/plugins/git.lua).

-- Todo comments. todo-comments is deferred behind the first real buffer
-- (lua/plugins/ui.lua), so load it before jumping; both functions are exported
-- from its init.lua.
map('n', ']t', function()
  pcall(vim.cmd.packadd, 'todo-comments.nvim')
  require('todo-comments').jump_next()
end, { desc = 'Next todo comment' })
map('n', '[t', function()
  pcall(vim.cmd.packadd, 'todo-comments.nvim')
  require('todo-comments').jump_prev()
end, { desc = 'Previous todo comment' })

-- Quickfix. pcall so the end of the list reports instead of throwing E553.
map('n', ']q', function()
  local ok, err = pcall(vim.cmd.cnext)
  if not ok then vim.notify(tostring(err):match '[^\n]*$' or 'No more quickfix items', vim.log.levels.WARN) end
end, { desc = 'Next quickfix item' })
map('n', '[q', function()
  local ok, err = pcall(vim.cmd.cprevious)
  if not ok then vim.notify(tostring(err):match '[^\n]*$' or 'No previous quickfix items', vim.log.levels.WARN) end
end, { desc = 'Previous quickfix item' })

-- Buffers, complementing <S-h> / <S-l> above.
map('n', ']b', '<cmd>bnext<CR>', { desc = 'Next buffer' })
map('n', '[b', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
