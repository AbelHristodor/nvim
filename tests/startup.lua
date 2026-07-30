-- Startup time regression gate.
--
-- Guards the spec's startup acceptance criterion.
--
-- Reference points measured on this machine:
--   bare nvim, no config, no plugins : ~17-18 ms  (the floor)
--   previous LazyVim install         : 167-277 ms (the baseline to beat)
--
-- BUDGET_MS is the spec's 60ms criterion. vim.pack.add is eager, so every
-- plugin added counts against it; the config buys headroom with `{ load = false }`
-- plus event-driven `packadd` (see lua/plugins/ui.lua for the pattern).
--
-- If this fails, the honest options are to defer another plugin or to raise the
-- budget with a recorded reason -- NOT to quietly relax it. The 60ms figure is
-- what the user approved.
--
-- Run via tests/run.sh, which supplies the mandatory -u flag.

local BUDGET_MS = 60
local RUNS = 5

local times = {}
for i = 1, RUNS do
  local log = ('/tmp/nvim-startup-%d.log'):format(i)
  os.remove(log)

  -- No -u here, deliberately: this measures a NORMAL startup, where Neovim
  -- discovers init.lua through NVIM_APPNAME. That is the number the user
  -- actually experiences. (-u is only needed for `-l` script runs, which skip
  -- user config.)
  --
  -- vim.v.progpath, not bare 'nvim', so this measures the same binary running
  -- the suite. clear_env = false keeps the inherited environment; a bare `env`
  -- table would drop XDG_* and TERM and change what gets loaded.
  local result = vim
    .system({ vim.v.progpath, '--headless', '--startuptime', log, '-c', 'qa' }, {
      clear_env = false,
      env = { NVIM_APPNAME = 'nvim-dev' },
    })
    :wait(30000)

  if result.code ~= 0 then
    print(('  FAIL child nvim exited %s'):format(tostring(result.code)))
    vim.cmd 'cq 1'
  end

  -- The `--- NVIM STARTED ---` line carries the cumulative total, e.g.
  --   030.284  000.084: --- NVIM STARTED ---
  -- Anchor on that marker rather than "last numeric line", so a trailing log
  -- entry cannot silently change what is being measured.
  local total
  local fh = io.open(log, 'r')
  if fh then
    for line in fh:lines() do
      local t = line:match '^(%d+%.%d+).*NVIM STARTED'
      if t then total = tonumber(t) end
    end
    fh:close()
  end

  if not total then
    print '  FAIL could not find "--- NVIM STARTED ---" in startuptime log'
    vim.cmd 'cq 1'
  end

  times[#times + 1] = total
  print(('  run %d: %.1f ms'):format(i, total))
end

table.sort(times)
local median = times[math.ceil(#times / 2)]
print(('\nmedian: %.1f ms (budget %d ms, floor ~17 ms, old config 167-277 ms)'):format(median, BUDGET_MS))

-- Report the slowest startup contributors on failure, so the next action is
-- obvious rather than requiring a separate profiling run.
if median > BUDGET_MS then
  print '\nslowest steps from the last run:'
  local fh = io.open('/tmp/nvim-startup-' .. RUNS .. '.log', 'r')
  if fh then
    local rows = {}
    for line in fh:lines() do
      local self_ms, label = line:match '^%d+%.%d+%s+%d+%.%d+%s+(%d+%.%d+): (.+)$'
      if self_ms then rows[#rows + 1] = { tonumber(self_ms), label } end
    end
    fh:close()
    table.sort(rows, function(a, b) return a[1] > b[1] end)
    for i = 1, math.min(8, #rows) do
      print(('  %6.2f ms  %s'):format(rows[i][1], rows[i][2]))
    end
  end
end

if median <= BUDGET_MS then
  print '  ok   startup within budget'
  vim.cmd 'cq 0'
else
  print(('  FAIL startup %.1f ms exceeds budget %d ms'):format(median, BUDGET_MS))
  vim.cmd 'cq 1'
end
