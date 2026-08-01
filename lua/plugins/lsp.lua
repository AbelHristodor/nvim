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

local project = require 'config.project'

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
  -- in this file -- see lua/config/project.lua for why.
  basedpyright = {
    root_markers = project.python_root_markers,

    -- The interpreter must be resolved PER ROOT, so it cannot live in the static
    -- settings table below. Without it, any project whose dependencies live in a
    -- venv reports "Import could not be resolved" / "Type of X is unknown" for
    -- every third-party import. See config.project.python_path.
    before_init = function(_, config)
      local root = config.root_dir
      if not root then return end

      local py = project.python_path(root)
      config.settings = vim.tbl_deep_extend('force', config.settings or {}, {
        python = { pythonPath = py },
        basedpyright = {
          analysis = {
            -- src-layout support, merged with whatever pyrightconfig.json
            -- already declares.
            extraPaths = project.python_extra_paths(root),
          },
        },
      })

      -- Warn only for a project that actually declares Python dependencies.
      -- A bare directory of scripts has nothing to resolve, and warning there is
      -- just noise.
      local declares_deps = vim.uv.fs_stat(root .. '/pyproject.toml') or vim.uv.fs_stat(root .. '/requirements.txt') or vim.uv.fs_stat(root .. '/setup.py')
      if not py and declares_deps then
        vim.notify(
          ('basedpyright: no virtualenv found in %s\nThird-party imports will not resolve. Create one with `uv venv` or `python -m venv .venv`.'):format(root),
          vim.log.levels.WARN
        )
      end
    end,

    settings = {
      basedpyright = {
        -- basedpyright's own hint decorations duplicate the diagnostics.
        disableTaggedHints = true,
        analysis = {
          -- Workspace-wide diagnostics would re-scan everything on each edit.
          diagnosticMode = 'openFilesOnly',
          exclude = project.exclude_globs,
          useLibraryCodeForTypes = true,
          autoImportCompletions = true,
          autoSearchPaths = true,
          typeCheckingMode = 'standard',

          -- QUIET THE UNTYPED-DEPENDENCY NOISE.
          --
          -- basedpyright defaults to a much stricter baseline than pyright: it
          -- reports every value whose type it cannot fully infer. Against any
          -- dependency that ships no type stubs that means a wall of "Type of X
          -- is unknown" on correct code.
          --
          -- Measured on one real 255-line module: 159 diagnostics total, of which
          -- only 7 were real errors -- 68 reportUnknownVariableType, 68
          -- reportUnknownMemberType, and the rest similar. Turning these off
          -- leaves genuine problems (missing imports, attribute errors, type
          -- mismatches) fully reported.
          diagnosticSeverityOverrides = {
            reportUnknownVariableType = 'none',
            reportUnknownMemberType = 'none',
            reportUnknownParameterType = 'none',
            reportUnknownArgumentType = 'none',
            reportUnknownLambdaType = 'none',
            reportMissingParameterType = 'none',
            reportMissingTypeStubs = 'none',
            reportUntypedFunctionDecorator = 'none',
            reportUntypedBaseClass = 'none',
            reportUnusedCallResult = 'none',
            reportAny = 'none',
            reportExplicitAny = 'none',
            reportImplicitOverride = 'none',
          },
        },
      },
    },
  },

  ruff = {
    root_markers = project.python_root_markers,
    -- basedpyright is the single source for hover, so silence ruff's.
    on_attach = function(client) client.server_capabilities.hoverProvider = false end,
  },

  -- TypeScript. Perf settings come from vtsls' own README: tsserver returns
  -- very large completion sets, and its default 3GB heap is low for big repos.
  vtsls = {
    root_markers = project.node_root_markers,
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

-- `pyright` is installed via mason-tool-installer as a fallback but is NOT
-- in `servers`: enabling both would run two type checkers over the same buffer,
-- doubling the analysis work this config exists to reduce. To switch, comment
-- out the basedpyright entry above and add:
--
--   pyright = {
--     root_markers = project.python_root_markers,
--     settings = { python = { analysis = {
--       diagnosticMode = 'openFilesOnly',
--       exclude = project.exclude_globs,
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

-- PYTHON INTERPRETER SWITCHING AT RUNTIME.
--
-- `before_init` resolves the interpreter once, when the server starts. That is
-- the wrong moment if you activate a venv afterwards, or if a project has several
-- (3.11 vs 3.12, or one per service): the server keeps whatever it was given and
-- there is no way to correct it from the shell, so imports stay unresolved.
--
-- basedpyright does accept a new interpreter at runtime via
-- workspace/didChangeConfiguration -- verified: pushing a new pythonPath into a
-- running client made previously-unresolved symbols resolve without a restart.
-- `:VenvSelect` does exactly that.

---Applies `py` as the Python interpreter for every running basedpyright client.
---@param py string absolute path to a python executable
local function set_python_path(py)
  local clients = vim.lsp.get_clients { name = 'basedpyright' }
  if #clients == 0 then
    vim.notify('No basedpyright client running', vim.log.levels.WARN)
    return
  end

  local venv = py:gsub('/bin/python$', '')
  for _, client in ipairs(clients) do
    local extra = vim.tbl_get(client.settings or {}, 'basedpyright', 'analysis', 'extraPaths') or {}
    -- Drop any previously-injected site-packages so switching venvs does not
    -- leave the old one on the path, then add the new one.
    local kept = vim.tbl_filter(function(p) return not p:find 'site%-packages$' end, extra)
    for _, lib in ipairs(vim.fn.glob(venv .. '/lib/python*/site-packages', false, true)) do
      kept[#kept + 1] = lib
    end

    client.settings = vim.tbl_deep_extend('force', client.settings or {}, {
      python = { pythonPath = py },
      basedpyright = { analysis = { extraPaths = kept } },
    })
    client:notify('workspace/didChangeConfiguration', { settings = client.settings })
  end

  -- Keep the environment in step so terminals, tests and DAP agree with the LSP.
  vim.env.VIRTUAL_ENV = venv
  if not (vim.env.PATH or ''):find(venv .. '/bin', 1, true) then vim.env.PATH = venv .. '/bin:' .. vim.env.PATH end

  vim.notify(('Python: %s'):format(py), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('VenvSelect', function()
  local root = vim.fs.root(0, project.python_root_markers) or vim.uv.cwd()
  local found = project.find_venvs(root)

  if #found == 0 then
    vim.notify(('No virtualenv found for %s.\nCreate one with `uv venv` or `python -m venv .venv`.'):format(root), vim.log.levels.WARN)
    return
  end

  vim.ui.select(found, { prompt = 'Python interpreter' }, function(choice)
    if choice then set_python_path(choice) end
  end)
end, { desc = 'Select the Python interpreter for the running LSP' })

vim.api.nvim_create_user_command('VenvCurrent', function()
  local client = vim.lsp.get_clients({ name = 'basedpyright' })[1]
  local py = client and vim.tbl_get(client.settings or client.config.settings or {}, 'python', 'pythonPath')
  vim.notify(('Python: %s\n$VIRTUAL_ENV: %s'):format(py or '(server default)', vim.env.VIRTUAL_ENV or '(unset)'), vim.log.levels.INFO)
end, { desc = 'Show the Python interpreter the LSP is using' })

vim.keymap.set('n', '<leader>cv', '<cmd>VenvSelect<CR>', { desc = 'Select Python venv' })

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

    -- Telescope's LSP pickers jump straight to a lone result rather than
    -- opening a picker (its __lsp.lua: `if #items == 1 and jump_type ~= "never"`),
    -- so `gd` stays a direct jump. That property is the whole point of this
    -- config; if a future picker lacks it, `gd` regresses to a menu.
    local builtin = require 'telescope.builtin'

    map('gd', builtin.lsp_definitions, 'Goto definition')
    map('gr', builtin.lsp_references, 'References')
    map('gI', builtin.lsp_implementations, 'Goto implementation')
    map('gy', builtin.lsp_type_definitions, 'Goto type definition')
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
    map('<leader>cs', builtin.lsp_document_symbols, 'Document symbols')
    map('<leader>cS', builtin.lsp_dynamic_workspace_symbols, 'Workspace symbols')

    local client = vim.lsp.get_client_by_id(event.data.client_id)

    -- Highlighting other references to the symbol under the cursor
    -- (textDocument/documentHighlight) is owned by snacks.words, set up in
    -- lua/plugins/editor.lua. It loads on this same LspAttach event and registers
    -- its own CursorMoved/ModeChanged handlers plus ]] / [[ navigation, so there
    -- is deliberately no documentHighlight autocmd here -- running both would
    -- draw the reference extmarks twice.

    if client and client:supports_method('textDocument/inlayHint', buf) then
      map('<leader>uh', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = buf }, { bufnr = buf }) end, 'Toggle inlay hints')
    end
  end,
})

-- lazydev.nvim: on-demand Neovim API types for Lua.
--
-- Worth having specifically because this repo IS a Neovim config. The lua_ls
-- on_init above already registers workspace libraries; lazydev is complementary
-- -- it resolves types per `require` as you type, rather than scanning the whole
-- runtime up front.
--
-- DEFERRED to the first Lua buffer. Not `load = false`: as documented in
-- lua/plugins/completion.lua, that still lands the plugin on runtimepath and
-- lets Neovim source its plugin/ files during the same startup.
--
-- Ordering is not a concern. lazydev pushes workspace/didChangeConfiguration to
-- clients that are already running (its lsp.lua:92), so it works whether it
-- loads before or after lua_ls starts.
local lazydev_ready = false

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Load lazydev on the first Lua buffer',
  group = vim.api.nvim_create_augroup('config-lazydev', { clear = true }),
  pattern = 'lua',
  callback = function()
    if lazydev_ready then return end
    lazydev_ready = true

    vim.pack.add { gh 'folke/lazydev.nvim' }
    require('lazydev').setup {
      library = {
        -- Types for vim.uv, which is a C module lua_ls cannot introspect.
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    }
  end,
})

-- Single owner of enablement. rust_analyzer is intentionally not in `servers`.
for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
  vim.lsp.enable(name)
end
