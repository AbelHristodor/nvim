-- fzf-lua: fuzzy finder backed by the native fzf binary.
--
-- Chosen over telescope and snacks.picker because filtering happens in
-- compiled code and `rg` restarts per keystroke, which scales better on large
-- repositories.
--
-- fzf-lua has no hard lazy.nvim dependency: the single reference in its
-- actions.lua is guarded by `if ... package.loaded.lazy then`, so it works
-- under vim.pack.

vim.pack.add { gh 'ibhagwan/fzf-lua' }

local fzf = require 'fzf-lua'

fzf.setup {
  -- Profiles: 'default-title' puts picker info in the window title;
  -- 'fzf-native' uses fzf's own previewer.
  { 'default-title', 'fzf-native' },
  winopts = {
    height = 0.85,
    width = 0.85,
    preview = { layout = 'flex', scrollbar = false },
  },
  files = {
    -- fd respects .gitignore and is faster than find.
    fd_opts = [[--color=never --type f --hidden --follow --exclude .git --exclude node_modules --exclude build --exclude target]],
  },
  grep = {
    rg_opts = [[--column --line-number --no-heading --color=always --smart-case --max-columns=4096 -g '!.git' -g '!node_modules' -g '!build' -g '!target']],
  },
  lsp = {
    -- Skip the picker UI entirely when there is exactly one result. This is
    -- what makes `gd` feel instant. It is fzf-lua's default; set explicitly
    -- so it survives future upstream changes.
    jump1 = true,
    async_or_timeout = 5000,
    includeDeclaration = false,
  },
}

-- Route vim.ui.select through fzf-lua (code actions, rename prompts, etc.).
-- Guarded: calling this twice prints "[Fzf-lua] vim.ui.select already
-- registered", which surfaces on any config reload (`:source $MYVIMRC`) and in
-- test runs that require this module after init.lua already did.
if not package.loaded['fzf-lua.providers.ui_select'] then fzf.register_ui_select() end

local map = vim.keymap.set

-- Find. LazyVim-style <leader>f prefix.
map('n', '<leader>ff', fzf.files, { desc = 'Find files' })
map('n', '<leader>fg', fzf.live_grep, { desc = 'Grep (live)' })
map('n', '<leader>fb', fzf.buffers, { desc = 'Buffers' })
map('n', '<leader>fr', fzf.oldfiles, { desc = 'Recent files' })
map('n', '<leader>fc', function() fzf.files { cwd = vim.fn.stdpath 'config' } end, { desc = 'Find config file' })
map('n', '<leader><leader>', fzf.buffers, { desc = 'Buffers' })

-- Search. <leader>s prefix.
map('n', '<leader>sh', fzf.helptags, { desc = 'Search help' })
map('n', '<leader>sk', fzf.keymaps, { desc = 'Search keymaps' })
map('n', '<leader>sc', fzf.commands, { desc = 'Search commands' })
map('n', '<leader>sr', fzf.resume, { desc = 'Resume last search' })
map('n', '<leader>sd', fzf.diagnostics_document, { desc = 'Document diagnostics' })
map('n', '<leader>sD', fzf.diagnostics_workspace, { desc = 'Workspace diagnostics' })
map({ 'n', 'v' }, '<leader>sw', fzf.grep_cword, { desc = 'Search word under cursor' })
map('n', '<leader>/', fzf.lgrep_curbuf, { desc = 'Grep current buffer' })

-- Git pickers.
map('n', '<leader>gc', fzf.git_commits, { desc = 'Git commits' })
map('n', '<leader>gs', fzf.git_status, { desc = 'Git status' })
map('n', '<leader>gb', fzf.git_branches, { desc = 'Git branches' })
