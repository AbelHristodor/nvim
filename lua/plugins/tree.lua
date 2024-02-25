return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    vim.keymap.set("n", "t", ":NvimTreeToggle<CR>")

    require("nvim-tree").setup {
      renderer = {
        group_empty = true,
      },
      filters = {
        dotfiles = false
      },
      git = {
        enable = true,
        ignore = false
      }
    }
  end,
}
