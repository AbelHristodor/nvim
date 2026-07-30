-- Measures textDocument/definition round-trip latency on a real Brazil Python
-- package -- the exact operation the user reported as taking "ages".
--
-- The previous config had two compounding causes:
--   1. lensline.nvim issued textDocument/references per visible function on
--      CursorMoved, so definition requests queued behind whole-workspace scans.
--   2. Brazil's build/ symlink pointed cross-volume at thousands of Python
--      files that pyright indexed. Measured with `find -L ~/workplace`: 99,186
--      reachable .py files. (Note plain `find` reports 0 because ~/workplace is
--      itself a symlink -- which is why the original survey undercounted.)
--
-- Run via tests/run.sh, which supplies the mandatory -u flag.

local BUDGET_MS = 500
local ATTACH_TIMEOUT_MS = 120000

local target = vim.fn.expand '~/workplace/Qualo/src/Qualo/src/backend_lambda/main.py'

if vim.fn.filereadable(target) ~= 1 then
  print(('SKIP: %s not readable (Brazil workspace not mounted?)'):format(target))
  vim.cmd 'cq 0'
end

print(('target: %s'):format(target))
vim.cmd.edit(target)
local buf = vim.api.nvim_get_current_buf()

-- Wait for basedpyright to attach and finish initialising.
local attached = vim.wait(ATTACH_TIMEOUT_MS, function()
  local clients = vim.lsp.get_clients { bufnr = buf, name = 'basedpyright' }
  return #clients > 0 and clients[1].initialized
end, 250)

if not attached then
  print '  FAIL basedpyright did not attach'
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients { bufnr = buf }) do
    names[#names + 1] = c.name
  end
  print('  attached clients: ' .. (next(names) and table.concat(names, ', ') or '(none)'))
  print '  hint: is basedpyright installed? :MasonInstall basedpyright'
  vim.cmd 'cq 1'
end

print '  ok   basedpyright attached'

local client = vim.lsp.get_clients({ bufnr = buf, name = 'basedpyright' })[1]
print(('  root: %s'):format(client.config.root_dir or '?'))

-- Confirm the exclusion actually reached the live client. Reading it off the
-- attached client (rather than off vim.lsp.config) proves it survived
-- resolution and was handed to the server, which is the property that matters.
local settings = client.settings or client.config.settings or {}
local exclude = vim.tbl_get(settings, 'basedpyright', 'analysis', 'exclude') or {}
if vim.tbl_contains(exclude, '**/build') then
  print(('  ok   server received **/build exclusion (%d globs)'):format(#exclude))
else
  print '  FAIL server did not receive the **/build exclusion'
  vim.cmd 'cq 1'
end

-- Find an identifier to jump from: the first symbol the document reports.
local sym_res = client:request_sync('textDocument/documentSymbol', {
  textDocument = vim.lsp.util.make_text_document_params(buf),
}, 20000, buf)

local pos
if sym_res and sym_res.result and sym_res.result[1] then
  local first = sym_res.result[1]
  local range = first.selectionRange or first.range or (first.location and first.location.range)
  if range then pos = { line = range.start.line, character = range.start.character } end
end
pos = pos or { line = 0, character = 0 }
print(('  jumping from line %d col %d'):format(pos.line, pos.character))

-- Time five definition requests and take the median.
local times = {}
for i = 1, 5 do
  local t0 = vim.uv.hrtime()
  local res = client:request_sync('textDocument/definition', {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = pos,
  }, BUDGET_MS * 8, buf)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  times[#times + 1] = ms
  print(('  request %d: %6.1f ms%s'):format(i, ms, (res and res.result) and '' or ' (no result)'))
end

table.sort(times)
local median = times[math.ceil(#times / 2)]
print(('\nmedian gd latency: %.1f ms (budget %d ms)'):format(median, BUDGET_MS))

if median <= BUDGET_MS then
  print '  ok   gd latency within budget'
  vim.cmd 'cq 0'
else
  print(('  FAIL gd latency %.1f ms exceeds budget %d ms'):format(median, BUDGET_MS))
  vim.cmd 'cq 1'
end
