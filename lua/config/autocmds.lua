-- Editor autocommands. Plugin-specific autocmds live with their plugin.

local function augroup(name) return vim.api.nvim_create_augroup('config-' .. name, { clear = true }) end

-- Briefly highlight yanked text.
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight on yank',
  group = augroup 'highlight-yank',
  callback = function() vim.hl.on_yank() end,
})

-- Reopen files at the last cursor position.
vim.api.nvim_create_autocmd('BufReadPost', {
  desc = 'Restore last cursor position',
  group = augroup 'last-loc',
  callback = function(ev)
    if vim.bo[ev.buf].filetype == 'gitcommit' then return end
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= line_count then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
  end,
})

-- Close throwaway windows with plain `q`.
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Close scratch filetypes with q',
  group = augroup 'close-with-q',
  pattern = { 'help', 'qf', 'man', 'lspinfo', 'checkhealth', 'notify', 'query' },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = ev.buf, silent = true, desc = 'Close window' })
  end,
})

-- Create missing parent directories on save.
vim.api.nvim_create_autocmd('BufWritePre', {
  desc = 'Auto-create parent directories',
  group = augroup 'auto-create-dir',
  callback = function(ev)
    if ev.match:match '^%w%w+://' then return end -- skip oil://, fugitive:// etc.
    vim.fn.mkdir(vim.fn.fnamemodify(vim.uv.fs_realpath(ev.match) or ev.match, ':p:h'), 'p')
  end,
})

-- Disable line numbers and wrap text in terminal buffers.
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Terminal buffer settings',
  group = augroup 'term-open',
  callback = function()
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = 'no'
  end,
})
