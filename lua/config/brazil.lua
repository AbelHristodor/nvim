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
M.exclude_globs = {
  '**/build', -- Brazil build farm symlink (cross-volume, thousands of files)
  '**/.bemol', -- Bemol IDE integration output
  '**/node_modules',
  '**/__pycache__',
  '**/target', -- Cargo
  '**/.venv',
  '**/env',
  '**/dist',
  '**/.tox',
  '**/.mypy_cache',
  '**/.pytest_cache',
  '**/.ruff_cache',
  '**/.git',
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

return M
