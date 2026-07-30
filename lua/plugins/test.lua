-- neotest: run and debug individual tests from the buffer.
--
-- Python uses the pytest adapter. Rust needs no adapter here: rustaceanvim
-- ships its own neotest adapter, which it registers when a Rust buffer opens.
--
-- FULLY DEFERRED, same reasoning as dap.lua: running a test is an explicit
-- action. Only the keymaps are eager.

-- NOT registered at startup, same reasoning as dap.lua: `load = false` still
-- lands the plugin on runtimepath and its plugin/ files get sourced anyway.
local neotest_specs = {
  gh 'nvim-neotest/neotest',
  gh 'nvim-neotest/neotest-python',
  gh 'nvim-neotest/nvim-nio',
  gh 'antoinemadec/FixCursorHold.nvim',
}

local neotest_ready = false

--- Load and configure neotest. Idempotent.
local function setup_neotest()
  if neotest_ready then return end
  neotest_ready = true

  vim.pack.add(neotest_specs)

  local adapters = {}

  local ok_py, py = pcall(function()
    return require 'neotest-python' {
      dap = { justMyCode = false },
      runner = 'pytest',
    }
  end)
  if ok_py then adapters[#adapters + 1] = py end

  -- rustaceanvim exposes its adapter as a module; include it when present.
  local ok_rust, rust_adapter = pcall(function() return require 'rustaceanvim.neotest' end)
  if ok_rust then adapters[#adapters + 1] = rust_adapter end

  require('neotest').setup {
    adapters = adapters,
    discovery = {
      -- Discovery walks the filesystem, which is slow on a large checkout.
      -- Tests are still found in the current file on demand.
      enabled = false,
    },
    status = { virtual_text = true },
    output = { open_on_run = false },
  }
end

--- Wraps a neotest action so the first invocation loads it first.
---@param fn fun(nt: table)
---@return fun()
local function lazy_neotest(fn)
  return function()
    setup_neotest()
    fn(require 'neotest')
  end
end

local map = vim.keymap.set
map('n', '<leader>tt', lazy_neotest(function(nt) nt.run.run() end), { desc = 'Run nearest test' })
map('n', '<leader>tf', lazy_neotest(function(nt) nt.run.run(vim.fn.expand '%') end), { desc = 'Run file tests' })
map('n', '<leader>tl', lazy_neotest(function(nt) nt.run.run_last() end), { desc = 'Run last test' })
map('n', '<leader>td', lazy_neotest(function(nt) nt.run.run { strategy = 'dap' } end), { desc = 'Debug nearest test' })
map('n', '<leader>ts', lazy_neotest(function(nt) nt.summary.toggle() end), { desc = 'Toggle test summary' })
map('n', '<leader>to', lazy_neotest(function(nt) nt.output.open { enter = true } end), { desc = 'Show test output' })
map('n', '<leader>tS', lazy_neotest(function(nt) nt.run.stop() end), { desc = 'Stop test run' })
