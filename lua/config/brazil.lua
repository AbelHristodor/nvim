-- Amazon Brazil workspace tuning. Pure data -- no side effects -- so it can be
-- required from lua/plugins/lsp.lua and asserted directly in tests.
--
-- Why this exists: each Brazil package contains a `build/` symlink pointing at
-- the build farm on a separate volume, e.g.
--
--   ~/workplace/Qualo/src/Qualo/build
--     -> /Volumes/workplace/Qualo/build/Qualo/Qualo-1.0/AL2_x86_64/DEV.STD.PTHREAD/build
--
-- One such tree measured 2,558 Python files. Language servers follow the
-- symlink and index all of them, paying cross-volume I/O for build output. In
-- the previous config this was a direct cause of multi-second `gd` latency,
-- because a definition request queued behind whole-workspace analysis.
--
-- Only 2 of ~36 packages in this workspace carry a pyrightconfig.json that
-- excludes it, so the exclusion is applied globally here instead.

local M = {}

--- Directories no language server should index.
---
--- NOTE what is deliberately NOT here: `.venv` and `.bemol`.
--- Excluding those was a real bug -- it hid every third-party dependency, so a
--- Brazil package reported "Import could not be resolved" and "Type of X is
--- unknown" for all of its imports. Exclusions must cover build OUTPUT, never
--- dependency sources. See M.python_path() below for how the venv is found.
M.exclude_globs = {
  '**/build', -- Brazil build farm symlink (cross-volume, thousands of files)
  '**/node_modules',
  '**/__pycache__',
  '**/target', -- Cargo
  '**/dist',
  '**/.tox',
  '**/.mypy_cache',
  '**/.pytest_cache',
  '**/.ruff_cache',
  '**/.hypothesis',
  '**/.git',
  '**/*.egg-info',
}

--- Root markers for Python. `Config` is the Brazil package manifest; listing it
--- keeps each server's scope to one package rather than the whole workspace.
--- `git rev-parse --show-toplevel` already returns the package directory
--- because each Brazil package is its own repository, so this reinforces
--- existing behaviour rather than fighting it.
M.python_root_markers = {
  'pyproject.toml',
  'setup.py',
  'setup.cfg',
  'pyrightconfig.json',
  'Config',
  '.git',
}

--- Root markers for TypeScript/JavaScript.
M.node_root_markers = {
  'tsconfig.json',
  'jsconfig.json',
  'package.json',
  'Config',
  '.git',
}

---Returns the Python interpreter to use for `root`, or nil to let the server guess.
---
--- WHY THIS IS NEEDED. Brazil resolves dependencies outside the package, so
--- without an interpreter basedpyright reports "Import could not be resolved" and
--- "Type of X is unknown" for every third-party import -- which is exactly what
--- happened in ~/workplace/PPdev/src/PPdev (159 diagnostics).
---
--- Search order, most specific first:
---   1. $VIRTUAL_ENV -- an already-activated venv always wins
---   2. <root>/.venv, then <root>/venv -- what `uv`/`python -m venv` create, and
---      what 5 of this workspace's packages actually have
---   3. the Bemol farm venv, resolved from pyrightconfig.json's venvPath
---
--- The farm venv is checked LAST on purpose. In PPdev its `bin/python` wrapper is
--- broken (it points at a CPython310 build path that no longer exists) and its
--- site-packages lacks aws_lambda_powertools, while the package's own .venv has
--- 72 working deps including it. So the local venv is both more reliable and more
--- complete. The farm path is still tried because packages built only via
--- brazil-build may have no local venv at all.
---@param root string package root directory
---@return string|nil interpreter absolute path to a python executable
function M.python_path(root)
  local function usable(path) return path and vim.fn.executable(path) == 1 and path or nil end

  -- 1. Activated venv.
  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= '' then
    local py = usable(vim.env.VIRTUAL_ENV .. '/bin/python')
    if py then return py end
  end

  -- 2. Venv inside the package.
  for _, dir in ipairs { '.venv', 'venv' } do
    local py = usable(('%s/%s/bin/python'):format(root, dir))
    if py then return py end
  end

  -- 3. Bemol farm venv, read from the package's own pyrightconfig.json so the
  --    path is never hard-coded to one workspace.
  local cfg = io.open(root .. '/pyrightconfig.json', 'r')
  if cfg then
    local body = cfg:read 'a'
    cfg:close()
    local venv_path = body:match '"venvPath"%s*:%s*"([^"]+)"'
    local venv_name = body:match '"venv"%s*:%s*"([^"]+)"'
    if venv_path and venv_name then
      local py = usable(('%s/%s/bin/python'):format(venv_path, venv_name))
      if py then return py end
    end
  end

  return nil
end

---Extra import roots for a Brazil package.
---
--- Two jobs:
---
--- 1. FIRST-PARTY code. Brazil packages put importable code under `src/`, with
---    `test/` importing from it. Without `src` on the path, every
---    `import mypackage.foo` fails ("could not be resolved") even though the file
---    is right there.
---
--- 2. THIRD-PARTY code. A package's own pyrightconfig.json may pin `venvPath` at
---    the Bemol farm venv, and that pin WINS over the pythonPath sent by the
---    client. In PPdev that farm venv is broken -- its `bin/python` points at a
---    CPython310 build path that no longer exists -- so third-party imports stay
---    unresolved even with a good interpreter configured. Measured on
---    src/ppdev_api/main.py: 159 errors as found, 7 once `src` and the real
---    interpreter are supplied, and those last 7 are exactly the farm-venv pin.
---    Adding the working venv's site-packages as an explicit extraPath routes
---    around it without editing anyone's pyrightconfig.json.
---@param root string
---@return string[]
function M.python_extra_paths(root)
  local paths = {}

  for _, dir in ipairs { 'src', 'test', 'scripts', 'configuration/aws_lambda' } do
    if vim.uv.fs_stat(('%s/%s'):format(root, dir)) then paths[#paths + 1] = dir end
  end

  -- Absolute site-packages of whichever venv python_path() picked, so
  -- third-party imports resolve even when pyrightconfig.json pins a broken venv.
  local py = M.python_path(root)
  if py then
    local venv = py:gsub('/bin/python$', '')
    for _, lib in ipairs(vim.fn.glob(venv .. '/lib/python*/site-packages', false, true)) do
      if vim.uv.fs_stat(lib) then paths[#paths + 1] = lib end
    end
  end

  return paths
end

return M
