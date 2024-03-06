-- Configure LSP
local on_attach = function(client, bufnr)
	local nmap = function(keys, func, desc)
		if desc then
			desc = "LSP: " .. desc
		end

		vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
	end

	-- Mappings.
	nmap("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
	nmap("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")

	nmap("gd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")
	nmap("gr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
	nmap("gI", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")
	nmap("<leader>D", require("telescope.builtin").lsp_type_definitions, "Type [D]efinition")
	nmap("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")

	-- See `:help K` for why this keymap
	nmap("K", vim.lsp.buf.hover, "Hover Documentation")
	nmap("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")

	-- Lesser used LSP functionality
	nmap("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
	nmap("<space>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd")
	nmap("<space>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove")
	nmap("<space>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, "[W]orkspace [L]ist")

	nmap("<space>f", function()
		vim.lsp.buf.format({ async = true })
	end, "[F]ormat")

	-- Create a command `:Format` local to the LSP buffer
	vim.api.nvim_buf_create_user_command(bufnr, "Format", function(_)
		vim.lsp.buf.format()
	end, { desc = "Format current buffer with LSP" })

	local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

	-- Format on save
	-- if client.supports_method('textDocument/formatting') then
	--   vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
	--   vim.api.nvim_create_autocmd('BufWritePre', {
	--     buffer = bufnr,
	--     group = augroup,
	--     callback = function()
	--       vim.lsp.buf.format({ bufnr = bufnr })
	--     end
	--   })
	-- end

	-- Enable completion triggered by <c-x><c-o>
	vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

	-- The following two autocommands are used to highlight references of the
	-- word under your cursor when your cursor rests there for a little while.
	--    See `:help CursorHold` for information about when this is executed
	--
	-- When you move your cursor, the highlights will be cleared (the second autocommand).
	if client and client.server_capabilities.documentHighlightProvider then
		vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
			buffer = bufnr,
			callback = vim.lsp.buf.document_highlight,
		})

		vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
			buffer = bufnr,
			callback = vim.lsp.buf.clear_references,
		})
	end
end

local golang_on_attach = function(client, bufnr)
	-- Autoapply code actions
	vim.api.nvim_create_autocmd("BufWritePre", {
		pattern = "*.go",
		callback = function()
			local params = vim.lsp.util.make_range_params()
			params.context = { only = { "source.organizeImports" } }

			local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params)
			for cid, res in pairs(result or {}) do
				for _, r in pairs(res.result or {}) do
					if r.edit then
						local enc = (vim.lsp.get_client_by_id(cid) or {}).offset_encoding or "utf-16"
						vim.lsp.util.apply_workspace_edit(r.edit, enc)
					end
				end
			end
		end,
	})

	return on_attach(client, bufnr)
end

return {
	-- LSP Configuration & Plugins
	"neovim/nvim-lspconfig",
	dependencies = {
		{
			"williamboman/mason.nvim",
			opts = function(_, opts)
				opts.ensure_installed = opts.ensure_installed or {}
				vim.list_extend(opts.ensure_installed, { "hadolint", "markdownlint", "marksman" })
			end,
		},
		"williamboman/mason-lspconfig.nvim",

		-- Useful status updates for LSP -- Notifications
		{ "j-hui/fidget.nvim", tag = "legacy", opts = {} },

		{
			"folke/trouble.nvim",
			dependencies = { "nvim-tree/nvim-web-devicons" },
			opts = {
				-- your configuration comes here
				-- or leave it empty to use the default settings
				-- refer to the configuration section below
			},
		},
		{
			"rmagatti/goto-preview",
			config = function()
				require("goto-preview").setup({
					default_mappings = true,
					dismiss_on_move = true,
				})
				-- Remaps to Peek Definitions etc
				-- nnoremap gpd <cmd>lua require('goto-preview').goto_preview_definition()<CR>
				-- nnoremap gpt <cmd>lua require('goto-preview').goto_preview_type_definition()<CR>
				-- nnoremap gpi <cmd>lua require('goto-preview').goto_preview_implementation()<CR>
				-- nnoremap gpD <cmd>lua require('goto-preview').goto_preview_declaration()<CR>
				-- nnoremap gP <cmd>lua require('goto-preview').close_all_win()<CR>
				-- nnoremap gpr <cmd>lua require('goto-preview').goto_preview_references()<CR>
			end,
		},
	},
	opts = {
		autoformat = true,
	},
	config = function()
		local mason = require("mason")
		local mason_lspconfig = require("mason-lspconfig")
		local lspconfig = require("lspconfig")

		-- Mason LSP Config
		-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
		local capabilities = vim.lsp.protocol.make_client_capabilities()
		capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities())

		local servers = {
			html = { filetypes = { "html", "twig", "hbs" } },
			lua_ls = {
				Lua = {
					diagnostics = {
						globals = { "vim" },
					},
					workspace = { checkThirdParty = false },
					telemetry = { enable = false },
				},
			},
			pyright = {
				filetypes = { "python" },
			},
			dockerls = {},
			docker_compose_language_service = {
				filetypes = { "Dockerfile", "docker-compose" },
			},
			terraformls = {},
			jsonls = {},
			bashls = {},
			tsserver = {},
		}

		mason.setup()

		mason_lspconfig.setup({
			ensure_installed = vim.tbl_keys(servers),
		})

		mason_lspconfig.setup_handlers({
			function(server_name)
				require("lspconfig")[server_name].setup({
					capabilities = capabilities,
					on_attach = on_attach,
					settings = servers[server_name],
					filetypes = (servers[server_name] or {}).filetypes,
				})
			end,
		})

		lspconfig.ruff_lsp.setup({
			on_attach = on_attach,
			capabilities = capabilities,
			filetypes = { "python" },
			root_dir = lspconfig.util.find_git_ancestor,
			cmd = { "ruff-lsp" },
			config = function()
				--> Disable hover provider in favor of pyright
				require("lazyvim.util").lsp.on_attach(function(client, _)
					if client.name == "ruff_lsp" then
						client.server_capabilities.hoverProvider = false
					end
				end)
			end,
		})

		lspconfig.gopls.setup({
			on_attach = golang_on_attach,
			capabilities = capabilities,
			opts = {
				settings = {
					gopls = {
						completeUnimported = true,
						usePlaceholders = true,
						analyses = {
							unusedparams = true,
						},
					},
				},
			},
		})
	end,
}
