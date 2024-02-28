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
      },
      update_focused_file = {
        enable = true,
      }
    }
  end,
}

-- -- Unless you are still migrating, remove the deprecated commands from v1.x
-- vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])
--
-- return {
--   "nvim-neo-tree/neo-tree.nvim",
--   version = "*",
--   dependencies = {
--     "nvim-lua/plenary.nvim",
--     "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
--     "MunifTanjim/nui.nvim",
--   },
--   config = function()
--     require('neo-tree').setup {}
--   end,
-- }
