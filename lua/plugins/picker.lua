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

-- fzf-lua is loaded eagerly (~19 modules, ~4ms). It could be deferred behind its
-- keymaps like dap/neotest, but lua/plugins/lsp.lua's LspAttach handler requires
-- it to build `gd`/`gr`/`gI` mappings, and an LspAttach can precede any picker
-- keypress. Paying 4ms here is cheaper than the indirection.
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

-- KEYMAPS MIRROR LAZYVIM EXACTLY.
--
-- Taken key-for-key from LazyVim's own fzf-lua extra
-- (lazyvim/plugins/extras/editor/fzf.lua) so existing muscle memory transfers
-- unchanged. Notable pairs that are easy to get backwards, and were wrong in an
-- earlier version of this file:
--   <leader>sg and <leader>/  are BOTH root-dir live grep
--   <leader>fg               is git_files, NOT grep
--   <leader>sd               is WORKSPACE diagnostics, <leader>sD is buffer
--   <leader>sc               is command HISTORY, <leader>sC is commands
--   <leader>sR               is resume (capital R)
-- Do not "tidy" these into a more logical scheme; matching LazyVim is the point.

-- Find files. <leader>f prefix.
map('n', '<leader>ff', fzf.files, { desc = 'Find Files (Root Dir)' })
map('n', '<leader>fB', fzf.buffers, { desc = 'Buffers (all)' })
map('n', '<leader>fb', function() fzf.buffers { sort_mru = true, sort_lastused = true } end, { desc = 'Buffers' })
map('n', '<leader>fc', function() fzf.files { cwd = vim.fn.stdpath 'config' } end, { desc = 'Find Config File' })
map('n', '<leader>fg', fzf.git_files, { desc = 'Find Files (git-files)' })
map('n', '<leader>fr', fzf.oldfiles, { desc = 'Recent' })
map('n', '<leader><space>', fzf.files, { desc = 'Find Files (Root Dir)' })

-- Grep. Both <leader>sg and <leader>/ are live grep, as in LazyVim.
map('n', '<leader>/', fzf.live_grep, { desc = 'Grep (Root Dir)' })
map('n', '<leader>sg', fzf.live_grep, { desc = 'Grep (Root Dir)' })
map('n', '<leader>sb', fzf.lines, { desc = 'Buffer Lines' })
map('n', '<leader>sw', fzf.grep_cword, { desc = 'Word (Root Dir)' })
map('x', '<leader>sw', fzf.grep_visual, { desc = 'Selection (Root Dir)' })

-- Search. <leader>s prefix.
map('n', '<leader>s/', fzf.search_history, { desc = 'Search History' })
map('n', '<leader>sa', fzf.autocmds, { desc = 'Auto Commands' })
map('n', '<leader>sc', fzf.command_history, { desc = 'Command History' })
map('n', '<leader>sC', fzf.commands, { desc = 'Commands' })
map('n', '<leader>sd', fzf.diagnostics_workspace, { desc = 'Diagnostics' })
map('n', '<leader>sD', fzf.diagnostics_document, { desc = 'Buffer Diagnostics' })
map('n', '<leader>sh', fzf.helptags, { desc = 'Help Pages' })
map('n', '<leader>sH', fzf.highlights, { desc = 'Search Highlight Groups' })
map('n', '<leader>sj', fzf.jumps, { desc = 'Jumplist' })
map('n', '<leader>sk', fzf.keymaps, { desc = 'Key Maps' })
map('n', '<leader>sl', fzf.loclist, { desc = 'Location List' })
map('n', '<leader>sM', fzf.man_pages, { desc = 'Man Pages' })
map('n', '<leader>sm', fzf.marks, { desc = 'Jump to Mark' })
map('n', '<leader>sq', fzf.quickfix, { desc = 'Quickfix List' })
map('n', '<leader>sR', fzf.resume, { desc = 'Resume' })
map('n', '<leader>:', fzf.command_history, { desc = 'Command History' })
map('n', '<leader>uC', fzf.colorschemes, { desc = 'Colorscheme with Preview' })

-- Git pickers.
map('n', '<leader>gc', fzf.git_commits, { desc = 'Commits' })
map('n', '<leader>gl', fzf.git_commits, { desc = 'Commits' })
map('n', '<leader>gd', fzf.git_diff, { desc = 'Git Diff (hunks)' })
map('n', '<leader>gs', fzf.git_status, { desc = 'Status' })
map('n', '<leader>gS', fzf.git_stash, { desc = 'Git Stash' })
