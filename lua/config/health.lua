-- :checkhealth config
--
-- Verifies external tools and the three performance invariants described in
-- README.md. Each invariant corresponds to a measured problem in the previous
-- config, not a style preference.

local M = {}

local function check_neovim()
  local verstr = tostring(vim.version())
  -- has() rather than vim.version.ge(): semver ranks a prerelease below its
  -- release, so ge(0.12.0-dev, 0.12) is false on nightly builds.
  if vim.fn.has 'nvim-0.12' == 1 then
    vim.health.ok(('Neovim version %s'):format(verstr))
  else
    vim.health.error(('Neovim %s is too old; this config requires 0.12+ (vim.pack)'):format(verstr))
  end
end

local function check_externals()
  local required = { 'git', 'rg', 'fd', 'fzf' }
  local optional = { 'make', 'cc', 'lazygit', 'cargo', 'rust-analyzer', 'go', 'node', 'npm', 'python3' }

  for _, exe in ipairs(required) do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(('found %s'):format(exe))
    else
      vim.health.error(('missing %s (required)'):format(exe))
    end
  end

  for _, exe in ipairs(optional) do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(('found %s'):format(exe))
    else
      vim.health.warn(('missing %s (optional)'):format(exe))
    end
  end
end

local function check_diagnostics_config()
  local cfg = vim.diagnostic.config()
  if type(cfg.virtual_text) == 'table' and cfg.virtual_text.current_line == false and type(cfg.virtual_lines) == 'table' then
    vim.health.ok 'hybrid diagnostics active (virtual_text off-cursor, virtual_lines on-cursor)'
  else
    vim.health.warn 'hybrid diagnostics not configured as designed; see lua/config/diagnostics.lua'
  end
end

--- INVARIANT 1: no reference-counting codelens. This was the primary cause of
--- multi-second `gd` latency in the previous config.
local function check_no_codelens()
  local offenders = { 'lensline', 'lsp_lines', 'nvim-lightbulb' }
  local found = {}
  for _, name in ipairs(offenders) do
    if package.loaded[name] then found[#found + 1] = name end
  end
  if #found == 0 then
    vim.health.ok 'no reference-counting codelens plugins loaded'
  else
    vim.health.error(('codelens plugin(s) loaded: %s -- these queue whole-workspace LSP requests ahead of gd'):format(table.concat(found, ', ')))
  end
end

--- INVARIANT 2: generated output stays excluded from language server indexing.
local function check_excludes()
  local ok, project = pcall(require, 'config.project')
  if not ok then
    vim.health.error 'config.project failed to load'
    return
  end
  if not vim.tbl_contains(project.exclude_globs, '**/build') then
    vim.health.error 'build/ exclusion missing -- language servers will index generated output'
    return
  end
  -- Excluding dependency sources hides every third-party import.
  for _, bad in ipairs { '**/.venv', '**/venv' } do
    if vim.tbl_contains(project.exclude_globs, bad) then
      vim.health.error(('%s must NOT be excluded -- it hides third-party imports'):format(bad))
      return
    end
  end
  vim.health.ok(('exclude globs sane (%d, build output only)'):format(#project.exclude_globs))
end

--- INVARIANT 3: heavy plugins stay off the startup path.
local function check_lazy_loading()
  local should_be_deferred = { 'blink.cmp', 'luasnip', 'dap', 'neotest', 'mason' }
  local eager = {}
  for _, name in ipairs(should_be_deferred) do
    if package.loaded[name] then eager[#eager + 1] = name end
  end
  -- Loaded-after-use is expected; this reports what it sees, so run
  -- :checkhealth early in a session for a meaningful answer.
  if #eager == 0 then
    vim.health.ok 'deferred plugins not yet loaded (startup path clean)'
  else
    vim.health.info(('loaded since startup: %s (expected if you have typed, debugged or run tests)'):format(table.concat(eager, ', ')))
  end
end

local function check_single_lsp_owner()
  if vim.lsp.is_enabled 'rust_analyzer' then
    vim.health.error 'rust_analyzer is enabled here, but rustaceanvim owns it -- it would start twice'
  else
    vim.health.ok 'rust_analyzer not enabled by this config (rustaceanvim owns it)'
  end

  if vim.lsp.is_enabled 'pyright' and vim.lsp.is_enabled 'basedpyright' then
    vim.health.error 'pyright AND basedpyright both enabled -- two type checkers over every buffer'
  else
    vim.health.ok 'exactly one Python type checker enabled'
  end

  -- mason-lspconfig is deferred, so only assert once it has actually loaded.
  local ms = package.loaded['mason-lspconfig.settings']
  if ms then
    if ms.current.automatic_enable == false then
      vim.health.ok 'mason-lspconfig automatic_enable is false (this config owns enablement)'
    else
      vim.health.error 'mason-lspconfig automatic_enable is on -- servers may be configured twice, overriding tuned settings'
    end
  else
    vim.health.info 'mason-lspconfig not loaded yet (deferred); automatic_enable is asserted by tests/health.lua'
  end
end

--- INVARIANT 4: exactly one plugin draws indent guides. mini.indentscope and
--- snacks.indent both write extmarks to the same columns; running both flickers.
local function check_single_indent_owner()
  local snacks_indent = package.loaded.snacks and Snacks.config.indent and Snacks.config.indent.enabled
  if snacks_indent and package.loaded['mini.indentscope'] then
    vim.health.error 'mini.indentscope AND snacks.indent both active -- overlapping extmarks will flicker'
  elseif snacks_indent then
    vim.health.ok 'indent guides: snacks.indent'
  else
    vim.health.ok 'indent guides: mini.indentscope (single owner)'
  end
end

function M.check()
  vim.health.start 'config: environment'
  check_neovim()
  check_externals()

  vim.health.start 'config: performance invariants'
  check_diagnostics_config()
  check_no_codelens()
  check_excludes()
  check_lazy_loading()
  check_single_lsp_owner()
  check_single_indent_owner()
end

return M
