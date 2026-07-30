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
--   tokyonight -- the colorscheme; deferring it means a visible flash of default
--                 colours, and every later plugin reads its highlight groups.
--   mini.icons -- lualine and the pickers ask for icons during their own setup.
--   lualine    -- draws the statusline on the first redraw.
-- Everything else is deferred until it is actually needed.

vim.pack.add {
  gh 'folke/tokyonight.nvim',
  gh 'nvim-mini/mini.nvim',
  gh 'nvim-lualine/lualine.nvim',
}

-- Deferred: no startup work, loaded on the events below.
vim.pack.add({
  gh 'folke/which-key.nvim',
  gh 'folke/todo-comments.nvim',
}, { load = false })

-- Colorscheme first, so later plugins pick up its highlight groups.
require('tokyonight').setup {
  style = 'night',
  styles = { comments = { italic = false } },
}
vim.cmd.colorscheme 'tokyonight-night'

-- Icons. A Nerd Font is configured in both wezterm and iTerm2.
require('mini.icons').setup()
MiniIcons.mock_nvim_web_devicons() -- for plugins that still require nvim-web-devicons

require('lualine').setup {
  options = {
    theme = 'tokyonight',
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

    vim.cmd.packadd 'todo-comments.nvim'
    require('todo-comments').setup { signs = false }
  end,
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
        { '<leader>s', group = 'Search' },
        { '<leader>t', group = 'Test' },
        { '<leader>u', group = 'UI/Toggle' },
        { '<leader>x', group = 'Diagnostics/Lists' },
      },
    }
  end,
})
