-- Colorscheme, statusline, keymap hints and small editing utilities.
--
-- PERFORMANCE MODEL. vim.pack.add is eager by default: it registers the plugin
-- AND sources its plugin/ and ftdetect/ files before returning. With ~15 plugins
-- that cost dominates startup, and this config exists to be fast.
--
-- `{ load = false }` registers the plugin and puts it on runtimepath but skips
-- sourcing plugin/ (equivalent to `:packadd!`). Verified: `require` still works
-- afterwards, so anything driven by an explicit require can be deferred to first
-- use without a `packadd` dance.
--
-- What must load eagerly and why:
--   catppuccin -- the colorscheme; deferring it means a visible flash of default
--                 colours, and every later plugin reads its highlight groups.
--   mini.icons -- lualine and the pickers ask for icons during their own setup.
--   lualine    -- draws the statusline on the first redraw.
-- Everything else is deferred until it is actually needed.

vim.pack.add {
  -- `name` is required: the repo is catppuccin/nvim, so vim.pack would infer the
  -- directory name "nvim" -- unhelpfully generic and a collision risk.
  { src = gh 'catppuccin/nvim', name = 'catppuccin' },
  gh 'nvim-mini/mini.nvim',
  gh 'nvim-lualine/lualine.nvim',
}

-- Deferred: no startup work, loaded on the events below.
vim.pack.add({
  gh 'folke/which-key.nvim',
  gh 'folke/todo-comments.nvim',
}, { load = false })

-- Colorscheme first, so later plugins pick up its highlight groups.
-- The repo is 'catppuccin/nvim' but the plugin directory and module are both
-- named `catppuccin`, so vim.pack's inferred name works out.
require('catppuccin').setup {
  flavour = 'macchiato',
  styles = { comments = {} }, -- no italics
  integrations = {
    treesitter = true,
    native_lsp = { enabled = true, underlines = { errors = { 'undercurl' }, warnings = { 'undercurl' } } },
    telescope = { enabled = true },
    gitsigns = true,
    mini = { enabled = true },
    which_key = true,
    nvim_tree = true,
    dap = true,
    dap_ui = true,
    blink_cmp = true,
    lsp_trouble = true,
    markdown = true,
  },
}
vim.cmd.colorscheme 'catppuccin-macchiato'

-- Icons. A Nerd Font is configured in both wezterm and iTerm2.
require('mini.icons').setup()
MiniIcons.mock_nvim_web_devicons() -- for plugins that still require nvim-web-devicons

require('lualine').setup {
  options = {
    -- catppuccin ships its lualine theme as `catppuccin-nvim`; passing
    --     'catppuccin' makes lualine emit a config notice and fall back.
    theme = 'catppuccin-nvim',
    globalstatus = true,
    section_separators = '',
    component_separators = '|',
  },
  sections = {
    lualine_c = { { 'filename', path = 1 } },
    lualine_x = { 'diagnostics', 'filetype' },
  },
}

local deferred = vim.api.nvim_create_augroup('config-ui-deferred', { clear = true })

-- Text objects and surroundings are only reachable from a real buffer, so
-- loading them on the first BufReadPost/BufNewFile costs nothing at startup.
-- `once` because both only need setting up a single time.
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  desc = 'Load editing plugins on first real buffer',
  group = deferred,
  once = true,
  callback = function()
    -- Extra text objects: va) vi" ci' etc. `aa`/`ii` avoid clashing with the
    -- built-in treesitter incremental-selection maps on Neovim 0.12.
    require('mini.ai').setup { mappings = { around_next = 'aa', inside_next = 'ii' }, n_lines = 500 }

    -- Add/delete/replace surroundings: saiw) sd' sr)'
    require('mini.surround').setup()

    -- Autopairing. Free here: mini.nvim is already loaded, so this is one
    -- setup() call rather than a new plugin.
    --
    -- ON <CR>, which the usual advice gets wrong for this config. blink.cmp's
    -- `default` preset does NOT map <CR> -- it accepts on <C-y>, mirroring
    -- built-in ins-completion (see lua/plugins/completion.lua). Probed live:
    -- with blink loaded, maparg('<CR>', 'i') is empty and mini.pairs then
    -- installs v:lua.MiniPairs.cr(). mini.pairs also guards this itself, only
    -- mapping <CR> when maparg is empty (its pairs.lua:557), so it yields to any
    -- future binding. Keeping it is what puts the cursor on a properly indented
    -- blank line when you press Enter between { and }.
    require('mini.pairs').setup {
      -- Command mode included so pairs work on the `:` line. Terminal excluded
      -- so they never interfere with a shell or lazygit.
      modes = { insert = true, command = true, terminal = false },
    }

    -- Indent guides. Owns them exclusively -- snacks.indent stays off, because
    -- two plugins drawing extmarks in the same columns flickers.
    require('mini.indentscope').setup {
      -- Default is an animated draw; instant keeps it from competing with
      -- cursor movement on large files.
      draw = { delay = 50, animation = require('mini.indentscope').gen_animation.none() },
      symbol = '│',
      options = { try_as_border = true },
    }

    vim.cmd.packadd 'todo-comments.nvim'
    require('todo-comments').setup { signs = false }
  end,
})

-- Indent guides are noise in throwaway and UI buffers. mini.indentscope reads
-- this buffer-local variable on each draw.
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Disable indent guides in scratch and UI buffers',
  group = deferred,
  pattern = { 'help', 'man', 'qf', 'lspinfo', 'checkhealth', 'trouble', 'NvimTree', 'gitcommit', 'markdown', 'snacks_notif', 'snacks_terminal' },
  callback = function(ev) vim.b[ev.buf].miniindentscope_disable = true end,
})

-- Terminal buffers have no meaningful indent structure.
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Disable indent guides in terminals',
  group = deferred,
  callback = function(ev) vim.b[ev.buf].miniindentscope_disable = true end,
})

-- which-key only matters once a mapping prefix is actually typed. Loading it on
-- the first keypress in normal mode keeps it off the startup path while still
-- being ready before the popup delay elapses.
vim.api.nvim_create_autocmd('SafeState', {
  desc = 'Load which-key after startup settles',
  group = deferred,
  once = true,
  callback = function()
    vim.cmd.packadd 'which-key.nvim'
    require('which-key').setup {
      delay = 200,
      icons = { mappings = vim.g.have_nerd_font },
      spec = {
        { '<leader>b', group = 'Buffer' },
        { '<leader>c', group = 'Code' },
        { '<leader>d', group = 'Debug' },
        { '<leader>f', group = 'Find/File' },
        { '<leader>g', group = 'Git' },
        { '<leader>q', group = 'Session/Quit' },
        { '<leader>s', group = 'Search' },
        { '<leader>t', group = 'Test' },
        { '<leader>u', group = 'UI/Toggle' },
        { '<leader>x', group = 'Diagnostics/Lists' },
      },
    }
  end,
})

-- trouble.nvim: a proper list for diagnostics, symbols and LSP results.
--
-- DEFERRED: registered on first use rather than at startup, for the reason
-- documented in lua/plugins/completion.lua (`load = false` alone still lets
-- Neovim source the plugin's plugin/ files during the same startup).
--
-- Keymaps mirror LazyVim's trouble extra exactly.
local trouble_specs = { gh 'folke/trouble.nvim' }
local trouble_ready = false

local function setup_trouble()
  if trouble_ready then return end
  trouble_ready = true
  vim.pack.add(trouble_specs)
  require('trouble').setup {}
end

---Runs a :Trouble subcommand, loading the plugin first.
---
--- Uses the Lua API rather than `vim.cmd('Trouble ...')`: the :Trouble command is
--- created by the plugin's own plugin/ file, which has not run yet at the moment
--- this keymap first fires, so the ex-command form errors on first press.
---@param mode string
---@param opts? table
---@return fun()
local function trouble(mode, opts)
  return function()
    setup_trouble()
    require('trouble').toggle(vim.tbl_extend('force', { mode = mode }, opts or {}))
  end
end

vim.keymap.set('n', '<leader>xx', trouble 'diagnostics', { desc = 'Diagnostics (Trouble)' })
vim.keymap.set('n', '<leader>xX', trouble('diagnostics', { filter = { buf = 0 } }), { desc = 'Buffer Diagnostics (Trouble)' })
vim.keymap.set('n', '<leader>cs', trouble 'symbols', { desc = 'Symbols (Trouble)' })
vim.keymap.set('n', '<leader>cS', trouble 'lsp', { desc = 'LSP references/definitions/... (Trouble)' })
vim.keymap.set('n', '<leader>xL', trouble 'loclist', { desc = 'Location List (Trouble)' })
vim.keymap.set('n', '<leader>xQ', trouble 'qflist', { desc = 'Quickfix List (Trouble)' })
vim.keymap.set('n', '<leader>xt', trouble 'todo', { desc = 'Todo (Trouble)' })
