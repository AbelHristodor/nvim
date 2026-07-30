-- conform.nvim: formatting, with a format-on-save toggle.
--
-- The toggle matters because projects vary in convention and an unexpected
-- reformat creates noisy diffs in code review.

vim.pack.add { gh 'stevearc/conform.nvim' }

-- Default on. `vim.g.autoformat` is the global switch; `vim.b.autoformat`
-- overrides per buffer.
vim.g.autoformat = true

require('conform').setup {
  notify_on_error = false,

  format_on_save = function(bufnr)
    -- Buffer-local setting wins over the global one.
    local enabled = vim.b[bufnr].autoformat
    if enabled == nil then enabled = vim.g.autoformat end
    if not enabled then return nil end
    return { timeout_ms = 1000, lsp_format = 'fallback' }
  end,

  default_format_opts = { lsp_format = 'fallback' },

  formatters_by_ft = {
    lua = { 'stylua' },
    python = { 'ruff_fix', 'ruff_format' }, -- fix (incl. import sort) then format
    rust = { 'rustfmt' },
    javascript = { 'prettier' },
    javascriptreact = { 'prettier' },
    typescript = { 'prettier' },
    typescriptreact = { 'prettier' },
    json = { 'prettier' },
    jsonc = { 'prettier' },
    yaml = { 'prettier' },
    markdown = { 'prettier' },
    html = { 'prettier' },
    css = { 'prettier' },
    toml = { 'taplo' },
    sh = { 'shfmt' },
    bash = { 'shfmt' },
    go = { 'goimports', 'gofumpt' },
  },

  formatters = {
    shfmt = { prepend_args = { '-i', '2', '-ci' } },
  },
}

-- Linting.
--
-- Most linters in this config need no runner:
--   * ruff       -- runs as a language server (see lua/plugins/lsp.lua)
--   * clippy     -- rust-analyzer's checkOnSave (see lua/plugins/rust.lua)
--   * shellcheck -- bash-language-server invokes it natively
--   * eslint     -- vtsls surfaces it when the project configures it
--
-- markdownlint is the exception: it is CLI-only, so it needs nvim-lint to turn
-- its output into diagnostics.
vim.pack.add { gh 'mfussenegger/nvim-lint' }

local lint = require 'lint'
lint.linters_by_ft = { markdown = { 'markdownlint-cli2' } }

-- MD013 is the line-length rule. Prose here is soft-wrapped, so a hard column
-- limit is noise rather than signal. Passed on the command line so no
-- per-project config file is required.
local md = lint.linters['markdownlint-cli2']
if md then md.args = vim.list_extend({ '--config', vim.fn.stdpath 'config' .. '/.markdownlint-cli2.yaml' }, md.args or {}) end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
  desc = 'Run linters',
  group = vim.api.nvim_create_augroup('config-lint', { clear = true }),
  callback = function() require('lint').try_lint() end,
})

local map = vim.keymap.set

map({ 'n', 'v' }, '<leader>cf', function() require('conform').format { async = true } end, { desc = 'Format buffer' })

map('n', '<leader>uf', function()
  vim.g.autoformat = not vim.g.autoformat
  vim.notify('Format on save (global): ' .. (vim.g.autoformat and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle format on save (global)' })

map('n', '<leader>uF', function()
  local current = vim.b.autoformat
  if current == nil then current = vim.g.autoformat end
  vim.b.autoformat = not current
  vim.notify('Format on save (buffer): ' .. (vim.b.autoformat and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle format on save (buffer)' })
