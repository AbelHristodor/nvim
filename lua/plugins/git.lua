-- Git: inline hunk signs plus lazygit in a terminal.

vim.pack.add {
  gh 'lewis6991/gitsigns.nvim',
  gh 'nvim-lua/plenary.nvim', -- required by neotest and others
}

require('gitsigns').setup {
  signs = {
    add = { text = '┃' },
    change = { text = '┃' },
    delete = { text = '_' },
    topdelete = { text = '‾' },
    changedelete = { text = '~' },
    untracked = { text = '┆' },
  },
  on_attach = function(buf)
    local gs = require 'gitsigns'
    local function map(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc }) end

    map('n', ']h', function() gs.nav_hunk 'next' end, 'Next hunk')
    map('n', '[h', function() gs.nav_hunk 'prev' end, 'Previous hunk')
    map({ 'n', 'v' }, '<leader>ghs', gs.stage_hunk, 'Stage hunk')
    map({ 'n', 'v' }, '<leader>ghr', gs.reset_hunk, 'Reset hunk')
    map('n', '<leader>ghp', gs.preview_hunk, 'Preview hunk')
    map('n', '<leader>ghb', function() gs.blame_line { full = true } end, 'Blame line')
    map('n', '<leader>ghd', gs.diffthis, 'Diff this')
  end,
}

-- diffview.nvim: side-by-side diffs, file history and 3-way merge resolution.
--
-- The one real git gap left by gitsigns (inline hunks) + lazygit (staging):
-- neither gives a proper diff view, a browsable file history, or a merge-conflict
-- editor. :DiffviewOpen diffs the working tree; :DiffviewFileHistory walks a
-- file's (or the repo's) commits.
--
-- DEFERRED to first use, as everywhere else in this config -- the spec is only
-- handed to vim.pack.add on the first keymap press.
local diffview_specs = {
  gh 'sindrets/diffview.nvim',
  gh 'nvim-lua/plenary.nvim', -- already on disk above; listed for correctness
}
local diffview_ready = false

---Loads diffview on first use, then runs a Diffview command.
---@param cmd string
---@return fun()
local function diffview(cmd)
  return function()
    if not diffview_ready then
      diffview_ready = true
      vim.pack.add(diffview_specs)
      require('diffview').setup {}
    end
    vim.cmd(cmd)
  end
end

vim.keymap.set('n', '<leader>gd', diffview 'DiffviewOpen', { desc = 'Diff View (open)' })
vim.keymap.set('n', '<leader>gD', diffview 'DiffviewClose', { desc = 'Diff View (close)' })
vim.keymap.set('n', '<leader>gf', diffview 'DiffviewFileHistory %', { desc = 'File History (current file)' })
vim.keymap.set('n', '<leader>gF', diffview 'DiffviewFileHistory', { desc = 'File History (repo)' })

-- lazygit in a floating terminal. The binary is already installed.
vim.keymap.set('n', '<leader>gg', function()
  if vim.fn.executable 'lazygit' ~= 1 then
    vim.notify('lazygit not found on PATH', vim.log.levels.ERROR)
    return
  end

  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.9)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
  })

  vim.fn.jobstart({ 'lazygit' }, {
    term = true,
    on_exit = function()
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
      -- Refresh signs for changes made inside lazygit.
      pcall(function() require('gitsigns').refresh() end)
    end,
  })
  vim.cmd.startinsert()
end, { desc = 'Lazygit' })
