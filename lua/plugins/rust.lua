-- rustaceanvim: rust-analyzer plus rust-analyzer-specific features that plain
-- LSP cannot express (grouped code actions, runnables, debuggables, macro
-- expansion, flyCheck).
--
-- Three constraints from its README:
--   1. There is NO setup() call. Configuration goes in vim.g.rustaceanvim and
--      must be set BEFORE the plugin initialises.
--   2. Config must NOT go in after/ftplugin/rust.lua -- that file loads after
--      initialisation. Keymaps do go there.
--   3. It owns rust_analyzer exclusively. Also running the lspconfig
--      rust_analyzer setup "may cause conflicts", which is why rust_analyzer
--      is absent from the servers table in lua/plugins/lsp.lua and
--      mason-lspconfig's automatic_enable is false.
--
-- Pinned to major 9: v9 requires Neovim 0.12, which this config targets.
-- Its README lists vim.pack first among install methods.
--
-- Costs ~0ms at startup regardless: rustaceanvim only initialises when a Rust
-- buffer opens, so no manual deferral is needed here.

vim.g.rustaceanvim = {
  server = {
    -- INLAY HINTS ON BY DEFAULT, IN RUST BUFFERS ONLY.
    --
    -- Two separate layers are involved and only one of them is the `inlayHints`
    -- table below. That table tells rust-analyzer WHICH hints to compute;
    -- Neovim's own renderer decides whether to DISPLAY them, and it defaults to
    -- off (vim.lsp.inlay_hint's state starts `enabled = false`). Configuring the
    -- server alone therefore shows nothing.
    --
    -- Enabled per buffer rather than globally: a global
    -- `vim.lsp.inlay_hint.enable(true)` would also switch them on for Python, Go
    -- and TypeScript, where the tuning here has not been done -- vtsls in
    -- lua/plugins/lsp.lua deliberately keeps variableTypes off.
    --
    -- `<leader>uh` (registered by the LspAttach handler in lua/plugins/lsp.lua)
    -- still toggles them; it reads the live state, so the first press now turns
    -- hints off rather than on.
    --
    -- Requesting hints this early can return an empty set, because
    -- rust-analyzer has not finished indexing when on_attach fires
    -- (neovim/neovim#26511). No workaround is needed here: rustaceanvim's
    -- `experimental/serverStatus` handler re-toggles hints for any buffer where
    -- they are already enabled once the server reports ready
    -- (server_status.lua), which is exactly this case.
    ---@param bufnr integer
    on_attach = function(_, bufnr) vim.lsp.inlay_hint.enable(true, { bufnr = bufnr }) end,

    default_settings = {
      ['rust-analyzer'] = {
        cargo = { allFeatures = true, buildScripts = { enable = true } },
        procMacro = { enable = true },
        checkOnSave = true,
        check = { command = 'clippy', extraArgs = { '--no-deps' } },
        inlayHints = {
          bindingModeHints = { enable = false },
          closureReturnTypeHints = { enable = 'never' },
          parameterHints = { enable = true },
        },
        files = {
          -- Keep rust-analyzer out of build output.
          excludeDirs = { 'build', 'target', 'node_modules' },
        },
      },
    },
  },
  tools = {
    float_win_config = { border = 'rounded' },
  },
}

vim.pack.add {
  { src = gh 'mrcjkb/rustaceanvim', version = vim.version.range '^9' },
}
