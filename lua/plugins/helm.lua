return {
	"towolf/vim-helm",
	ft = 'helm',
	config = function()
		local lspconfig = require("lspconfig")
		lspconfig.helm_ls.setup {
			settings = {
				['helm-ls'] = {
					yamlls = {
						path = "yaml-language-server",
					}
				}
			}
		}

		lspconfig.yamlls.setup {}
	end,
}
