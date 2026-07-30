-- Language servers.
--
-- ENABLEMENT OWNERSHIP -- read before changing anything here.
--
-- mason-lspconfig's `automatic_enable` feature calls BOTH
-- `vim.lsp.config(name, cfg)` and `vim.lsp.enable(name)`, where `cfg` comes
-- from its bundled `mason-lspconfig.lsp.<server>` module when one exists
-- (see its features/automatic_enable.lua). If it ran alongside the explicit
-- loop at the bottom of this file, every server would be configured twice and
-- mason-lspconfig's bundled settings could displace the tuning below --
-- including the basedpyright excludes that fix the `gd` latency.
--
-- Therefore: automatic_enable = false, and this file is the single owner of
-- enablement. rust_analyzer is deliberately absent from `servers` because
-- rustaceanvim owns it (see lua/plugins/rust.lua); its README warns that also
-- running the lspconfig setup "may cause conflicts".

local brazil = require 'config.brazil'

vim.pack.add {
  gh 'neovim/nvim-lspconfig',
  gh 'mason-org/mason.nvim',
  gh 'mason-org/mason-lspconfig.nvim',
  gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  gh 'j-hui/fidget.nvim',
}

require('fidget').setup {} -- LSP progress in the corner

---@type table<string, vim.lsp.Config>
local servers = {
  -- Python: basedpyright owns navigation and hover; ruff owns lint and
  -- organize-imports. The `exclude` list is the single most important setting
  -- in this file -- see lua/config/brazil.lua for why.
  basedpyright = {
    root_markers = brazil.python_root_markers,
    settings = {
      basedpyright = {
        analysis = {
          -- Workspace-wide diagnostics would re-scan everything on each edit.
          diagnosticMode = 'openFilesOnly',
          exclude = brazil.exclude_globs,
          useLibraryCodeForTypes = true,
          autoImportCompletions = true,
          typeCheckingMode = 'standard',
        },
      },
    },
  },

  ruff = {
    root_markers = brazil.python_root_markers,
    -- basedpyright is the single source for hover, so silence ruff's.
    on_attach = function(client) client.server_capabilities.hoverProvider = false end,
  },

  -- TypeScript. Perf settings come from vtsls' own README: tsserver returns
  -- very large completion sets, and its default 3GB heap is low for big repos.
  vtsls = {
    root_markers = brazil.node_root_markers,
    settings = {
      vtsls = {
        experimental = {
          completion = {
            enableServerSideFuzzyMatch = true,
            entriesLimit = 250,
          },
        },
      },
      typescript = {
        tsserver = { maxTsServerMemory = 8192 },
        preferences = { includePackageJsonAutoImports = 'off' },
        inlayHints = {
          parameterNames = { enabled = 'literals' },
          variableTypes = { enabled = false },
        },
      },
    },
  },

  lua_ls = {
    on_init = function(client)
      -- stylua owns formatting.
      client.server_capabilities.documentFormattingProvider = false

      -- Skip the expensive runtime-library scan when the project has its own
      -- .luarc.json.
      if client.workspace_folders then
        local path = client.workspace_folders[1].name
        if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
      end

      client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua or {}, {
        runtime = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
        workspace = {
          checkThirdParty = false,
          library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
            '${3rd}/luv/library',
          }),
        },
      })
    end,
    settings = {
      Lua = {
        format = { enable = false },
        diagnostics = { globals = { 'vim', 'gh', 'MiniIcons' } },
        completion = { callSnippet = 'Replace' },
      },
    },
  },

  gopls = {
    settings = {
      gopls = {
        analyses = { unusedparams = true },
        staticcheck = true,
      },
    },
  },

  bashls = {},
  jsonls = {},
  yamlls = {},
  taplo = {},
  marksman = {},
}

-- `pyright` is installed via mason-tool-installer as a fallback (the spec keeps
-- it in case basedpyright misbehaves on Brazil layouts) but is deliberately NOT
-- in `servers`: enabling both would run two type checkers over the same buffer,
-- doubling the analysis work this config exists to reduce. To switch, comment
-- out the basedpyright entry above and add:
--
--   pyright = {
--     root_markers = brazil.python_root_markers,
--     settings = { python = { analysis = {
--       diagnosticMode = 'openFilesOnly',
--       exclude = brazil.exclude_globs,
--     } } },
--   }
--
-- Note the settings key is `python`, not `basedpyright`.

require('mason').setup {}

-- See the ownership note at the top of this file.
require('mason-lspconfig').setup { automatic_enable = false }

require('mason-tool-installer').setup {
  ensure_installed = {
    -- Servers (Mason package names, verified against the registry).
    'basedpyright',
    'pyright', -- fallback only; NOT enabled (see note above)
    'ruff',
    'vtsls',
    'lua-language-server',
    'gopls',
    'bash-language-server',
    'json-lsp',
    'yaml-language-server',
    'taplo',
    'marksman',
    -- Formatters and linters (used by lua/plugins/format.lua).
    'stylua',
    'prettier',
    'shfmt',
    'shellcheck',
    'gofumpt',
    'goimports',
    'markdownlint-cli2',
    -- Debug adapters (used by lua/plugins/dap.lua).
    'debugpy',
    'codelldb',
  },
  run_on_start = false, -- installing during startup would slow it down
}

-- Buffer-local LSP keymaps. LazyVim-style, to preserve muscle memory.
--
-- NOTE: no codelens anywhere. Reference-counting codelens was the primary
-- cause of the multi-second `gd` latency this config exists to fix: it issued
-- textDocument/references per visible function on CursorMoved, and definition
-- requests queued behind those whole-workspace scans.
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP buffer keymaps',
  group = vim.api.nvim_create_augroup('config-lsp-attach', { clear = true }),
  callback = function(event)
    local buf = event.buf
    local function map(keys, fn, desc, mode) vim.keymap.set(mode or 'n', keys, fn, { buffer = buf, desc = 'LSP: ' .. desc }) end

    local fzf = require 'fzf-lua'

    map('gd', fzf.lsp_definitions, 'Goto definition')
    map('gr', fzf.lsp_references, 'References')
    map('gI', fzf.lsp_implementations, 'Goto implementation')
    map('gy', fzf.lsp_typedefs, 'Goto type definition')
    map('gD', vim.lsp.buf.declaration, 'Goto declaration')
    map('K', vim.lsp.buf.hover, 'Hover')
    -- Signature help is deliberately NOT on `gK`: lua/config/diagnostics.lua
    -- owns `gK` as the virtual_lines toggle (per the spec's keymap table), and
    -- a buffer-local LspAttach map would silently shadow it in exactly the
    -- buffers where the toggle is most useful.
    map('<leader>ck', vim.lsp.buf.signature_help, 'Signature help')
    map('<C-k>', vim.lsp.buf.signature_help, 'Signature help', 'i')
    map('<leader>cr', vim.lsp.buf.rename, 'Rename')
    map('<leader>ca', vim.lsp.buf.code_action, 'Code action', { 'n', 'x' })
    map('<leader>cs', fzf.lsp_document_symbols, 'Document symbols')
    map('<leader>cS', fzf.lsp_live_workspace_symbols, 'Workspace symbols')

    local client = vim.lsp.get_client_by_id(event.data.client_id)

    -- Highlight other references to the symbol under the cursor. This uses
    -- textDocument/documentHighlight, which is buffer-local and cheap --
    -- unlike textDocument/references, which is workspace-wide.
    if client and client:supports_method('textDocument/documentHighlight', buf) then
      local hl_group = vim.api.nvim_create_augroup('config-lsp-highlight', { clear = false })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        buffer = buf,
        group = hl_group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer = buf,
        group = hl_group,
        callback = vim.lsp.buf.clear_references,
      })
      vim.api.nvim_create_autocmd('LspDetach', {
        group = vim.api.nvim_create_augroup('config-lsp-detach', { clear = true }),
        callback = function(ev2)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds { group = 'config-lsp-highlight', buffer = ev2.buf }
        end,
      })
    end

    if client and client:supports_method('textDocument/inlayHint', buf) then
      map('<leader>uh', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = buf }, { bufnr = buf }) end, 'Toggle inlay hints')
    end
  end,
})

-- Single owner of enablement. rust_analyzer is intentionally not in `servers`.
for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
  vim.lsp.enable(name)
end
