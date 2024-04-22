return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {
    options = {
      theme = 'nord'
    },
    sections = {
      lualine_x = { 'encoding', 'fileformat', 'filetype' },
    }
  },
}
