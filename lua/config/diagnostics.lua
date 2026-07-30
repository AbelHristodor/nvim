-- Hybrid diagnostic display.
--
-- `virtual_text.current_line = false` is not "disabled" -- it is a three-state
-- flag (see :help vim.diagnostic.Opts.VirtualText):
--   true  -> only the cursor line
--   false -> every line EXCEPT the cursor line
--   nil   -> every line
--
-- Pairing `virtual_text { current_line = false }` with
-- `virtual_lines { current_line = true }` gives compact markers everywhere and
-- full multi-line detail on the line under the cursor. This matters for long
-- Rust and TypeScript type errors that virtual text truncates.
--
-- Neither handler issues an LSP request: diagnostics are pushed by the server
-- via textDocument/publishDiagnostics and rendered as extmarks. This is
-- categorically unlike codelens, which pulls per symbol. See the "no codelens"
-- rule in the design spec.

--- Show the jumped-to diagnostic as virtual lines. Mirrors
--- *diagnostic-on-jump-example* in :help diagnostic.
---@param diagnostic? vim.Diagnostic
---@param bufnr integer
local function on_jump(diagnostic, bufnr)
  if not diagnostic then return end
  vim.diagnostic.show(diagnostic.namespace, bufnr, { diagnostic }, {
    virtual_lines = { current_line = true },
    virtual_text = false,
  })
end

vim.diagnostic.config {
  underline = { severity = { min = vim.diagnostic.severity.WARN } },
  update_in_insert = false,
  severity_sort = true,

  virtual_text = {
    current_line = false, -- everywhere except the cursor line
    source = 'if_many',
    prefix = '●',
    spacing = 2,
  },

  virtual_lines = {
    current_line = true, -- full detail on the cursor line only
  },

  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '󰅙 ',
      [vim.diagnostic.severity.WARN] = '󰀦 ',
      [vim.diagnostic.severity.INFO] = '󰋼 ',
      [vim.diagnostic.severity.HINT] = '󰌵 ',
    },
  },

  float = { border = 'rounded', source = 'if_many' },
  jump = { on_jump = on_jump },
}

-- Toggle virtual_lines. Mirrors *diagnostic-toggle-virtual-lines-example*, but
-- on <leader>ud rather than the doc's `gK`: LazyVim binds `gK` to LSP signature
-- help and matching that muscle memory takes priority. <leader>u* is LazyVim's
-- own UI-toggle prefix, so this fits its scheme.
vim.keymap.set('n', '<leader>ud', function()
  local enabled = vim.diagnostic.config().virtual_lines
  if enabled then
    vim.diagnostic.config { virtual_lines = false }
    vim.notify('Diagnostic virtual_lines: off', vim.log.levels.INFO)
  else
    vim.diagnostic.config { virtual_lines = { current_line = true } }
    vim.notify('Diagnostic virtual_lines: on', vim.log.levels.INFO)
  end
end, { desc = 'Toggle diagnostic virtual_lines' })

-- Diagnostic navigation. vim.diagnostic.jump respects the on_jump handler above.
vim.keymap.set('n', ']d', function() vim.diagnostic.jump { count = 1, float = false } end, { desc = 'Next diagnostic' })
vim.keymap.set('n', '[d', function() vim.diagnostic.jump { count = -1, float = false } end, { desc = 'Previous diagnostic' })
vim.keymap.set('n', ']e', function() vim.diagnostic.jump { count = 1, severity = vim.diagnostic.severity.ERROR, float = false } end, { desc = 'Next error' })
vim.keymap.set(
  'n',
  '[e',
  function() vim.diagnostic.jump { count = -1, severity = vim.diagnostic.severity.ERROR, float = false } end,
  { desc = 'Previous error' }
)
vim.keymap.set('n', '<leader>cd', vim.diagnostic.open_float, { desc = 'Line diagnostics' })
