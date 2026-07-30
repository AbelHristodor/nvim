-- Debugging. debugpy (Python) and codelldb (Rust) are installed via
-- mason-tool-installer in lua/plugins/lsp.lua.
--
-- Rust debugging is wired automatically by rustaceanvim, which detects
-- codelldb and builds DAP configurations itself.
--
-- FULLY DEFERRED. Debugging is an explicit action, so nothing here belongs on
-- the startup path. The keymaps below are the only thing registered eagerly;
-- the first one pressed loads the stack. This keeps ~40 modules (dap, dapui,
-- nio, dap-python) out of startup entirely.

-- NOT registered at startup. `{ load = false }` is insufficient: it still puts
-- the plugin on runtimepath, so Neovim sources its plugin/ files later in the
-- same startup (measured with blink.cmp: sourced at 135ms, after init.lua
-- finished at 119ms). Registering inside setup_dap() keeps them off entirely.
-- vim.pack.add is idempotent, so calling it on first use is safe.
local dap_specs = {
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio', -- required by dap-ui
  gh 'theHamsta/nvim-dap-virtual-text',
  gh 'mfussenegger/nvim-dap-python',
}

local dap_ready = false

--- Load and configure the debug stack. Idempotent.
local function setup_dap()
  if dap_ready then return end
  dap_ready = true

  vim.pack.add(dap_specs)

  local dap = require 'dap'
  local dapui = require 'dapui'

  dapui.setup {}
  require('nvim-dap-virtual-text').setup {}

  -- Python. Point debugpy at Mason's copy so it works regardless of the
  -- project's virtualenv.
  local debugpy = vim.fn.stdpath 'data' .. '/mason/packages/debugpy/venv/bin/python'
  if vim.fn.executable(debugpy) == 1 then
    require('dap-python').setup(debugpy)
  else
    -- Fall back to whatever python3 is active.
    require('dap-python').setup 'python3'
  end

  -- Open and close the UI automatically with the debug session.
  dap.listeners.after.event_initialized['dapui'] = function() dapui.open {} end
  dap.listeners.before.event_terminated['dapui'] = function() dapui.close {} end
  dap.listeners.before.event_exited['dapui'] = function() dapui.close {} end

  -- Breakpoint signs.
  vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DiagnosticError' })
  vim.fn.sign_define('DapStopped', { text = '▶', texthl = 'DiagnosticWarn', linehl = 'Visual' })

  return dap, dapui
end

--- Wraps a dap action so the first invocation loads the stack first.
---@param fn fun(dap: table, dapui: table)
---@return fun()
local function lazy_dap(fn)
  return function()
    setup_dap()
    fn(require 'dap', require 'dapui')
  end
end

local map = vim.keymap.set
map('n', '<leader>db', lazy_dap(function(dap) dap.toggle_breakpoint() end), { desc = 'Toggle breakpoint' })
map('n', '<leader>dB', lazy_dap(function(dap) dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ') end), { desc = 'Conditional breakpoint' })
map('n', '<leader>dc', lazy_dap(function(dap) dap.continue() end), { desc = 'Continue' })
map('n', '<leader>di', lazy_dap(function(dap) dap.step_into() end), { desc = 'Step into' })
map('n', '<leader>do', lazy_dap(function(dap) dap.step_over() end), { desc = 'Step over' })
map('n', '<leader>dO', lazy_dap(function(dap) dap.step_out() end), { desc = 'Step out' })
map('n', '<leader>dt', lazy_dap(function(dap) dap.terminate() end), { desc = 'Terminate' })
map('n', '<leader>dr', lazy_dap(function(dap) dap.repl.toggle() end), { desc = 'Toggle REPL' })
map('n', '<leader>du', lazy_dap(function(_, dapui) dapui.toggle {} end), { desc = 'Toggle debug UI' })
