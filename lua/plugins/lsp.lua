-- Configure LSP
local on_attach = function(client, bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end


  -- Mappings.
  nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
  nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  nmap('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<space>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd')
  nmap('<space>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove')
  nmap('<space>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist')

  nmap('<space>f', function() vim.lsp.buf.format { async = true } end, '[F]ormat')


  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })

  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

  client.server_capabilities.hoverProvider = false
end

return {
  -- LSP Configuration & Plugins
  'neovim/nvim-lspconfig',
  dependencies = {
    'williamboman/mason.nvim',
    'williamboman/mason-lspconfig.nvim',

    -- Useful status updates for LSP -- Notifications
    { 'j-hui/fidget.nvim', tag = 'legacy', opts = {} },

  },
  config = function()
    local mason = require("mason")
    local mason_lspconfig = require("mason-lspconfig")
    local lspconfig = require('lspconfig')

    -- Mason LSP Config
    -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

    local servers = {
      html = { filetypes = { 'html', 'twig', 'hbs' } },

      lua_ls = {
        Lua = {
          diagnostics = {
            globals = { 'vim' },
          },
          workspace = { checkThirdParty = false },
          telemetry = { enable = false },
        },
      },
    }

    mason.setup()

    mason_lspconfig.setup {
      ensure_installed = vim.tbl_keys(servers),
    }

    mason_lspconfig.setup_handlers {
      function(server_name)
        require('lspconfig')[server_name].setup {
          capabilities = capabilities,
          on_attach = on_attach,
          settings = servers[server_name],
          filetypes = (servers[server_name] or {}).filetypes,
        }
      end,
    }

    lspconfig.ruff_lsp.setup({
      on_attach = on_attach,
      capabilities = capabilities,
      filetypes = { 'python' },
      root_dir = lspconfig.util.find_git_ancestor,
      cmd = { 'ruff-lsp' },
    })

    lspconfig.pyright.setup({
      on_attach = on_attach,
      capabilities = capabilities,
      filetypes = { 'python' },
    })

  end,
}
