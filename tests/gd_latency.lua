-- Measures textDocument/definition round-trip latency -- the operation that was
-- reported as "taking ages" in the previous config.
--
-- Two compounding causes were found and fixed:
--   1. A codelens plugin issued textDocument/references per visible function on
--      CursorMoved, so definition requests queued behind whole-workspace scans on
--      a single-threaded server. See the "no codelens" rule in the design spec.
--   2. Generated output was being indexed. A `build/` tree, often a symlink onto
--      another volume, can dwarf the real source: one measured checkout reached
--      ~99k reachable .py files versus ~130 actually being edited.
--
-- The target project is generated in a temp directory, so this test is
-- self-contained and does not depend on any particular checkout being present.
--
-- Run via tests/run.sh, which supplies the mandatory -u flag.

local BUDGET_MS = 500
local ATTACH_TIMEOUT_MS = 120000

-- A src-layout package with a local import, so definition resolution has to
-- consult the project's own path configuration rather than just the open file.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/src/demo', 'p')

local function write(path, lines)
  local fh = assert(io.open(path, 'w'))
  fh:write(table.concat(lines, '\n') .. '\n')
  fh:close()
end

write(root .. '/pyproject.toml', { '[project]', 'name = "demo"', 'version = "0.1.0"' })

write(root .. '/src/demo/helpers.py', {
  'def compute(value: int) -> int:',
  '    return value + 1',
  '',
  '',
  'class Widget:',
  '    def __init__(self, size: int) -> None:',
  '        self.size = size',
  '',
  '    def scaled(self, factor: int) -> int:',
  '        return self.size * factor',
})

write(root .. '/src/demo/main.py', {
  'from demo.helpers import Widget, compute',
  '',
  '',
  'def run() -> int:',
  '    widget = Widget(size=3)',
  '    return compute(widget.scaled(2))',
})

local target = root .. '/src/demo/main.py'
print(('target: %s'):format(target))

--- Remove the generated project. Called before every exit path.
local function cleanup() vim.fn.delete(root, 'rf') end

vim.cmd.edit(target)
local buf = vim.api.nvim_get_current_buf()

-- Wait for basedpyright to attach and finish initialising.
local attached = vim.wait(ATTACH_TIMEOUT_MS, function()
  local clients = vim.lsp.get_clients { bufnr = buf, name = 'basedpyright' }
  return #clients > 0 and clients[1].initialized
end, 250)

if not attached then
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients { bufnr = buf }) do
    names[#names + 1] = c.name
  end
  cleanup()
  print '  FAIL basedpyright did not attach'
  print('  attached clients: ' .. (next(names) and table.concat(names, ', ') or '(none)'))
  print '  hint: is basedpyright installed? :MasonInstall basedpyright'
  vim.cmd 'cq 1'
end

print '  ok   basedpyright attached'

local client = vim.lsp.get_clients({ bufnr = buf, name = 'basedpyright' })[1]
print(('  root: %s'):format(client.config.root_dir or '?'))

-- Confirm the exclusions actually reached the live client. Reading them off the
-- attached client (rather than off vim.lsp.config) proves they survived
-- resolution and were handed to the server, which is the property that matters.
local settings = client.settings or client.config.settings or {}
local exclude = vim.tbl_get(settings, 'basedpyright', 'analysis', 'exclude') or {}
if vim.tbl_contains(exclude, '**/build') then
  print(('  ok   server received **/build exclusion (%d globs)'):format(#exclude))
else
  cleanup()
  print '  FAIL server did not receive the **/build exclusion'
  vim.cmd 'cq 1'
end

-- Jump from the `compute` call on the last line back to its definition in
-- helpers.py -- a cross-file resolution, which is the realistic case.
local pos
for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  local col = line:find 'compute%(widget'
  if col then
    pos = { line = i - 1, character = col + 1 }
    break
  end
end
pos = pos or { line = 0, character = 0 }
print(('  jumping from line %d col %d'):format(pos.line, pos.character))

-- Time five definition requests and take the median.
local times = {}
local resolved = false
for i = 1, 5 do
  local t0 = vim.uv.hrtime()
  local res = client:request_sync('textDocument/definition', {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = pos,
  }, BUDGET_MS * 8, buf)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  times[#times + 1] = ms
  if res and res.result and not vim.tbl_isempty(res.result) then resolved = true end
  print(('  request %d: %6.1f ms%s'):format(i, ms, (res and res.result) and '' or ' (no result)'))
end

-- A fast "no result" is not a pass: it would mean the server never resolved the
-- symbol, which is exactly the failure mode this test exists to catch.
if resolved then
  print '  ok   definition resolved across files'
else
  cleanup()
  print '  FAIL definition never resolved -- check python_path / extraPaths'
  vim.cmd 'cq 1'
end

table.sort(times)
local median = times[math.ceil(#times / 2)]
print(('\nmedian gd latency: %.1f ms (budget %d ms)'):format(median, BUDGET_MS))

cleanup()

if median <= BUDGET_MS then
  print '  ok   gd latency within budget'
  vim.cmd 'cq 0'
else
  print(('  FAIL gd latency %.1f ms exceeds budget %d ms'):format(median, BUDGET_MS))
  vim.cmd 'cq 1'
end
