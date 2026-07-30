-- Project detection helpers: which directories to ignore, where a project root
-- is, and which Python interpreter belongs to it.
--
-- Pure data and pure functions -- no side effects -- so this can be required from
-- lua/plugins/lsp.lua and asserted directly in tests.

local M = {}

--- Directories no language server should index.
---
--- These are build OUTPUT and caches. Indexing them is pure cost: often a large
--- tree, sometimes on a different volume, and nothing in it is a file you edit.
--- Excluding a generated tree was worth several seconds of go-to-definition
--- latency on a large checkout.
---
--- NOTE what is deliberately absent: `.venv`, `venv` and anything else holding
--- dependency SOURCES. Excluding those was a real bug -- it hid every third-party
--- package, so a project reported "Import could not be resolved" and "Type of X is
--- unknown" for all of its imports. Exclusions must cover generated files, never
--- dependencies.
M.exclude_globs = {
  '**/build', -- generated output; often a symlink to a separate volume
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

--- Root markers for Python.
---
--- Ordered most-specific first. Anchoring on a project marker rather than `.git`
--- alone keeps a language server scoped to one project instead of a whole
--- multi-project checkout, which is what keeps workspace-wide requests cheap.
M.python_root_markers = {
  'pyproject.toml',
  'setup.py',
  'setup.cfg',
  'pyrightconfig.json',
  '.git',
}

--- Root markers for TypeScript/JavaScript.
M.node_root_markers = {
  'tsconfig.json',
  'jsconfig.json',
  'package.json',
  '.git',
}

---Returns the Python interpreter to use for `root`, or nil to let the server guess.
---
--- WHY THIS IS NEEDED. Without an explicit interpreter, basedpyright reports
--- "Import could not be resolved" and "Type of X is unknown" for every
--- third-party import in any project whose dependencies are not installed
--- alongside the interpreter found on PATH.
---
--- Search order, most specific first:
---   1. $VIRTUAL_ENV -- an already-activated venv always wins
---   2. <root>/.venv, then <root>/venv -- what `uv` and `python -m venv` create
---   3. a venv declared by the project's own pyrightconfig.json (venvPath + venv)
---
--- The declared venv is checked LAST on purpose: such a path is often stale or
--- points at a partially-built environment, while a local `.venv` is usually what
--- the developer is actually running. It is still tried, because some projects
--- have no local venv at all.
---@param root string project root directory
---@return string|nil interpreter absolute path to a python executable
function M.python_path(root)
  local function usable(path) return path and vim.fn.executable(path) == 1 and path or nil end

  -- 1. Activated venv.
  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= '' then
    local py = usable(vim.env.VIRTUAL_ENV .. '/bin/python')
    if py then return py end
  end

  -- 2. Venv inside the project.
  for _, dir in ipairs { '.venv', 'venv' } do
    local py = usable(('%s/%s/bin/python'):format(root, dir))
    if py then return py end
  end

  -- 3. Venv declared by pyrightconfig.json, so no path is hard-coded here.
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

---Finds candidate virtualenvs for a project, most likely first.
---
--- Used by the `:VenvSelect` picker in lua/plugins/lsp.lua. Looks in the project
--- itself and in the conventional out-of-tree locations that uv, virtualenvwrapper
--- and poetry use, so a venv stored outside the repo is still offered.
---@param root string
---@return string[] python interpreter paths
function M.find_venvs(root)
  local seen, out = {}, {}
  local function add(py)
    if py and vim.fn.executable(py) == 1 and not seen[py] then
      seen[py] = true
      out[#out + 1] = py
    end
  end

  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= '' then add(vim.env.VIRTUAL_ENV .. '/bin/python') end

  for _, dir in ipairs { '.venv', 'venv', 'env', '.direnv/python-*' } do
    for _, hit in ipairs(vim.fn.glob(('%s/%s/bin/python'):format(root, dir), false, true)) do
      add(hit)
    end
  end

  -- Out-of-tree venv managers. `~/.virtualenvs` is virtualenvwrapper's default;
  -- the Library path is where poetry keeps them on macOS.
  local name = vim.fn.fnamemodify(root, ':t')
  for _, pattern in ipairs {
    vim.env.HOME .. '/.virtualenvs/*/bin/python',
    vim.env.HOME .. '/.local/share/virtualenvs/*/bin/python',
    vim.env.HOME .. '/Library/Caches/pypoetry/virtualenvs/*/bin/python',
    vim.env.HOME .. '/.cache/pypoetry/virtualenvs/*/bin/python',
  } do
    for _, hit in ipairs(vim.fn.glob(pattern, false, true)) do
      -- Prefer ones whose directory name mentions the project.
      if hit:lower():find(name:lower(), 1, true) then add(hit) end
    end
  end

  return out
end

---Extra import roots for a Python project.
---
--- Two jobs:
---
--- 1. FIRST-PARTY code. A src-layout project keeps importable code under `src/`,
---    with `test/` importing from it. Without `src` on the path, every
---    `import mypackage.foo` fails even though the file is right there.
---
--- 2. THIRD-PARTY code. A project's own pyrightconfig.json may pin a `venvPath`,
---    and that pin WINS over the pythonPath sent by the client -- so if the pinned
---    environment is stale, third-party imports stay unresolved even with a good
---    interpreter configured. Adding the working venv's site-packages as an
---    explicit extraPath routes around that without editing project files.
---@param root string
---@return string[]
function M.python_extra_paths(root)
  local paths = {}

  for _, dir in ipairs { 'src', 'test', 'tests', 'lib' } do
    if vim.uv.fs_stat(('%s/%s'):format(root, dir)) then paths[#paths + 1] = dir end
  end

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
