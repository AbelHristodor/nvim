-- rustaceanvim keymaps. Its README specifies that keymaps belong here, while
-- configuration must live in vim.g.rustaceanvim (set in lua/plugins/rust.lua)
-- because this file loads after the plugin initialises.
--
-- `K` and `<leader>ca` are intentionally re-mapped here, overriding the generic
-- versions set by the LspAttach handler in lua/plugins/lsp.lua. Both are
-- buffer-local and after/ftplugin runs later, so rustaceanvim's richer
-- implementations win in Rust buffers only. This is not a collision to "fix":
-- vim.lsp.buf.code_action cannot render rust-analyzer's grouped actions.

local buf = vim.api.nvim_get_current_buf()
local function map(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { buffer = buf, desc = desc }) end

map('<leader>ca', function() vim.cmd.RustLsp 'codeAction' end, 'Code action (grouped)')
map('<leader>cR', function() vim.cmd.RustLsp 'runnables' end, 'Runnables')
map('<leader>cD', function() vim.cmd.RustLsp 'debuggables' end, 'Debuggables')
map('<leader>ce', function() vim.cmd.RustLsp 'explainError' end, 'Explain error')
map('<leader>cm', function() vim.cmd.RustLsp 'expandMacro' end, 'Expand macro')
map('<leader>cp', function() vim.cmd.RustLsp 'parentModule' end, 'Parent module')
map('<leader>cC', function() vim.cmd.RustLsp 'openCargo' end, 'Open Cargo.toml')
map('<leader>cdo', function() vim.cmd.RustLsp 'openDocs' end, 'Open docs.rs')
map('K', function() vim.cmd.RustLsp { 'hover', 'actions' } end, 'Hover actions')
