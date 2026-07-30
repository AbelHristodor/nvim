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
