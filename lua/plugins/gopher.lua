return {
  "olexsmir/gopher.nvim",
  dependencies = { -- dependencies
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  ft = "go",                 -- for which file types
  config = function(_, opts) -- your configuration
    require("gopher").setup(opts)
  end,
  build = function() -- package pre-installation build
    vim.cmd("GoInstallDeps")
  end,
}
