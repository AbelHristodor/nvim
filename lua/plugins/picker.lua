-- telescope: fuzzy finder.
--
-- Chosen over fzf-lua by request. The native fzf sorter extension does the
-- filtering in compiled C, which is what keeps it usable on a Brazil workspace
-- (`find -L ~/workplace` reaches ~99k Python files). Without that extension
-- telescope's Lua sorter is noticeably slower on large result sets.
--
-- On `gd` latency: telescope's LSP pickers jump straight to the result when
-- there is exactly one, rather than showing a picker (verified in its
-- builtin/__lsp.lua: `if #items == 1 and opts.jump_type ~= "never"`). So
-- go-to-definition stays a direct jump, which is the behaviour this config was
-- built to protect.

vim.pack.add {
  gh 'nvim-lua/plenary.nvim',
  gh 'nvim-telescope/telescope.nvim',
  -- Built with make; the PackChanged hook in init.lua compiles it.
  gh 'nvim-telescope/telescope-fzf-native.nvim',
  gh 'nvim-telescope/telescope-ui-select.nvim',
}

local telescope = require 'telescope'
local actions = require 'telescope.actions'

telescope.setup {
  defaults = {
    prompt_prefix = '   ',
    selection_caret = '  ',
    path_display = { 'truncate' },
    sorting_strategy = 'ascending',
    layout_strategy = 'horizontal',
    layout_config = {
      horizontal = { prompt_position = 'top', preview_width = 0.55 },
      width = 0.87,
      height = 0.80,
    },
    -- Keep the pickers out of build output. Mirrors lua/config/brazil.lua, which
    -- excludes the same directories from language server indexing.
    file_ignore_patterns = {
      '^%.git/',
      '/%.git/',
      'node_modules/',
      '/build/',
      '/target/',
      '%.bemol/',
      '__pycache__/',
      '%.mypy_cache/',
      '%.pytest_cache/',
      '%.ruff_cache/',
      '%.venv/',
      'dist/',
    },
    mappings = {
      i = {
        ['<C-j>'] = actions.move_selection_next,
        ['<C-k>'] = actions.move_selection_previous,
        ['<C-q>'] = actions.smart_send_to_qflist + actions.open_qflist,
        ['<Esc>'] = actions.close, -- close from insert mode directly
      },
    },
  },

  pickers = {
    find_files = {
      -- fd respects .gitignore and is faster than find.
      find_command = {
        'fd',
        '--type',
        'f',
        '--hidden',
        '--follow',
        '--strip-cwd-prefix',
        '--exclude',
        '.git',
        '--exclude',
        'node_modules',
        '--exclude',
        'build',
        '--exclude',
        'target',
      },
    },
    buffers = {
      sort_mru = true,
      sort_lastused = true,
      ignore_current_buffer = false,
    },
  },

  extensions = {
    fzf = {
      fuzzy = true,
      override_generic_sorter = true,
      override_file_sorter = true,
      case_mode = 'smart_case',
    },
    ['ui-select'] = { require('telescope.themes').get_dropdown {} },
  },
}

-- The native sorter is the reason this is fast; load it if it compiled.
pcall(telescope.load_extension, 'fzf')
-- Route vim.ui.select (code actions, rename prompts) through telescope.
pcall(telescope.load_extension, 'ui-select')

local builtin = require 'telescope.builtin'
local map = vim.keymap.set

-- KEYMAPS MIRROR LAZYVIM EXACTLY.
--
-- Taken key-for-key from LazyVim so existing muscle memory transfers. Pairs that
-- are easy to get backwards, and were wrong in an earlier version of this file:
--   <leader>sg and <leader>/  are BOTH root-dir live grep
--   <leader>fg               is git_files, NOT grep
--   <leader>sd               is WORKSPACE diagnostics, <leader>sD is buffer
--   <leader>sc               is command HISTORY, <leader>sC is commands
--   <leader>sR               is resume (capital R)
-- Do not "tidy" these into a more logical scheme; matching LazyVim is the point.

-- Find files. <leader>f prefix.
map('n', '<leader>ff', builtin.find_files, { desc = 'Find Files (Root Dir)' })
map('n', '<leader><space>', builtin.find_files, { desc = 'Find Files (Root Dir)' })
map('n', '<leader>fg', builtin.git_files, { desc = 'Find Files (git-files)' })
map('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
map('n', '<leader>fB', function() builtin.buffers { sort_mru = false } end, { desc = 'Buffers (all)' })
map('n', '<leader>fr', builtin.oldfiles, { desc = 'Recent' })
map('n', '<leader>fc', function() builtin.find_files { cwd = vim.fn.stdpath 'config' } end, { desc = 'Find Config File' })

-- Grep. Both <leader>/ and <leader>sg are live grep, as in LazyVim.
map('n', '<leader>/', builtin.live_grep, { desc = 'Grep (Root Dir)' })
map('n', '<leader>sg', builtin.live_grep, { desc = 'Grep (Root Dir)' })
map('n', '<leader>sb', builtin.current_buffer_fuzzy_find, { desc = 'Buffer Lines' })
map('n', '<leader>sw', builtin.grep_string, { desc = 'Word (Root Dir)' })
map('x', '<leader>sw', builtin.grep_string, { desc = 'Selection (Root Dir)' })

-- Search. <leader>s prefix.
map('n', '<leader>s/', builtin.search_history, { desc = 'Search History' })
map('n', '<leader>sa', builtin.autocommands, { desc = 'Auto Commands' })
map('n', '<leader>sc', builtin.command_history, { desc = 'Command History' })
map('n', '<leader>sC', builtin.commands, { desc = 'Commands' })
map('n', '<leader>sd', builtin.diagnostics, { desc = 'Diagnostics' })
map('n', '<leader>sD', function() builtin.diagnostics { bufnr = 0 } end, { desc = 'Buffer Diagnostics' })
map('n', '<leader>sh', builtin.help_tags, { desc = 'Help Pages' })
map('n', '<leader>sH', builtin.highlights, { desc = 'Search Highlight Groups' })
map('n', '<leader>sj', builtin.jumplist, { desc = 'Jumplist' })
map('n', '<leader>sk', builtin.keymaps, { desc = 'Key Maps' })
map('n', '<leader>sl', builtin.loclist, { desc = 'Location List' })
map('n', '<leader>sM', builtin.man_pages, { desc = 'Man Pages' })
map('n', '<leader>sm', builtin.marks, { desc = 'Jump to Mark' })
map('n', '<leader>sq', builtin.quickfix, { desc = 'Quickfix List' })
map('n', '<leader>sR', builtin.resume, { desc = 'Resume' })
map('n', '<leader>:', builtin.command_history, { desc = 'Command History' })
map('n', '<leader>uC', builtin.colorscheme, { desc = 'Colorscheme with Preview' })

-- Git pickers.
map('n', '<leader>gc', builtin.git_commits, { desc = 'Commits' })
map('n', '<leader>gl', builtin.git_commits, { desc = 'Commits' })
map('n', '<leader>gs', builtin.git_status, { desc = 'Status' })
map('n', '<leader>gS', builtin.git_stash, { desc = 'Git Stash' })
