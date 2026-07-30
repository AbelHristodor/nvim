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

-- Mason's bin directory must be on PATH before any server starts.
--
-- Normally `require('mason').setup()` prepends it, but mason is deferred here to
-- keep ~45 modules off the startup path -- and a server can be spawned by
-- vim.lsp.enable() long before anything triggers that load. Without this, every
-- Mason-installed server silently fails to attach: `vim.fn.executable
-- 'lua-language-server'` returns 0 and no client appears, with no error shown.
-- Found exactly that way during end-to-end testing.
--
-- Prepending the path directly is ~0ms and removes the ordering dependency
-- entirely.
local mason_bin = vim.fn.stdpath 'data' .. '/mason/bin'
if not (vim.env.PATH or ''):find(mason_bin, 1, true) then vim.env.PATH = mason_bin .. ':' .. vim.env.PATH end

-- nvim-lspconfig must load eagerly: it ships the per-server defaults that
-- vim.lsp.config() merges with the tuning below.
vim.pack.add { gh 'neovim/nvim-lspconfig' }

-- DEFERRED. Mason (~45 modules) is a package manager -- only needed when
-- installing tools or when a server actually starts. fidget (~16 modules) only
-- draws progress once a server reports it. Neither is needed to open a file, so
-- both move off the startup path; together they were ~25ms of ~254 startup
-- requires. Loaded on LspAttach and on the :Mason* commands below.
vim.pack.add({
  gh 'mason-org/mason.nvim',
  gh 'mason-org/mason-lspconfig.nvim',
  gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  gh 'j-hui/fidget.nvim',
}, { load = false })

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

-- Mason setup, run once on first need rather than at startup. Idempotent, and
-- guarded so repeated triggers are cheap.
local mason_ready = false
local function setup_mason()
  if mason_ready then return end
  mason_ready = true

  for _, p in ipairs { 'mason.nvim', 'mason-lspconfig.nvim', 'mason-tool-installer.nvim' } do
    pcall(vim.cmd.packadd, p)
  end

  require('mason').setup {}

  -- See the ownership note at the top of this file. automatic_enable must stay
  -- false: this file already called vim.lsp.enable for every server it owns, and
  -- mason-lspconfig would otherwise re-configure them with its bundled settings.
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
end

-- Mason's own commands need it loaded first, so each is registered as a stub
-- that loads mason and then re-dispatches.
--
-- `vim.cmd` is deliberately deferred with vim.schedule here. The stub is running
-- as the handler for `cmd`, and setup_mason() replaces that command definition
-- mid-execution; re-dispatching synchronously can hit the half-registered
-- command. Scheduling lets the current command finish first. Found because
-- `MasonToolsInstall` reported success while mason itself never loaded, so
-- nothing was installed.
for _, cmd in ipairs { 'Mason', 'MasonInstall', 'MasonUninstall', 'MasonUninstallAll', 'MasonLog', 'MasonUpdate', 'MasonToolsInstall', 'MasonToolsUpdate' } do
  vim.api.nvim_create_user_command(cmd, function(opts)
    pcall(vim.api.nvim_del_user_command, cmd)
    setup_mason()
    local target, args = cmd, opts.args
    vim.schedule(function()
      local ok, err = pcall(vim.cmd, vim.trim(('%s %s'):format(target, args)))
      if not ok then vim.notify(('%s failed: %s'):format(target, err), vim.log.levels.ERROR) end
    end)
  end, { nargs = '*', desc = 'Load mason, then run ' .. cmd })
end

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

    -- A server is running, so progress reporting is now worth its cost.
    -- Scheduled so it never delays the attach itself.
    vim.schedule(function()
      if not package.loaded.fidget then
        pcall(vim.cmd.packadd, 'fidget.nvim')
        pcall(function() require('fidget').setup {} end)
      end
      setup_mason()
    end)

    local fzf = require 'fzf-lua'

    map('gd', fzf.lsp_definitions, 'Goto definition')
    map('gr', fzf.lsp_references, 'References')
    map('gI', fzf.lsp_implementations, 'Goto implementation')
    map('gy', fzf.lsp_typedefs, 'Goto type definition')
    map('gD', vim.lsp.buf.declaration, 'Goto declaration')
    map('K', vim.lsp.buf.hover, 'Hover')
    -- `gK` is signature help, matching LazyVim. The diagnostics virtual_lines
    -- toggle lives on <leader>ud instead (lua/config/diagnostics.lua) -- an
    -- earlier version had them the other way round, which silently shadowed
    -- LazyVim's binding in exactly the buffers where it is used most.
    map('gK', vim.lsp.buf.signature_help, 'Signature help')
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
