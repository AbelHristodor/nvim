return {
	-- Highlight, edit, and navigate code
	"nvim-treesitter/nvim-treesitter",
	dependencies = {
		"nvim-treesitter/nvim-treesitter-textobjects",
	},
	build = ":TSUpdate",
	config = function()
		local configs = require("nvim-treesitter.configs")

		configs.setup({
			ensure_installed = {
				"c",
				"lua",
				"vim",
				"vimdoc",
				"query",
				"rust",
				"javascript",
				"html",
				"python",
				"json",
				"bash",
				"cmake",
				"dockerfile",
				"htmldjango",
				"markdown",
				"markdown_inline",
				"regex",
				"sql",
				"toml",
				"yaml",
				"css",
				"csv",
				"comment",
				"terraform",
				"hcl",
				"go",
				"typescript",
			},
			auto_install = false,
			highlight = { enable = true },
			indent = { enable = true },
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<c-space>",
					node_incremental = "<c-space>",
					scope_incremental = "<c-s>",
					node_decremental = "<M-space>",
				},
			},
		})
	end,
}
