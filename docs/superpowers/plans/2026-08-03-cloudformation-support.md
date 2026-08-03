# CloudFormation Template Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make this Neovim config first-class for AWS CloudFormation templates in YAML and JSON — no spurious intrinsic-tag errors, schema-driven completion/validation, `cfn-lint` diagnostics, and correct formatting on save.

**Architecture:** Content-based detection sets a composite filetype (`yaml.cloudformation` / `json.cloudformation`) plus `vim.b.cloudformation`. The existing `yamlls`/`jsonls`/prettier keep firing on the `yaml`/`json` component unchanged; a new `cloudformation` component targets `cfn-lint` (nvim-lint) and a runtime schema push (LSP `workspace/didChangeConfiguration`, the same idiom the config already uses for Python interpreter switching). Detection logic lives in a new `lua/config/cloudformation.lua`, mirroring `lua/config/project.lua`.

**Tech Stack:** Lua, Neovim 0.12 (`vim.pack`, `vim.lsp.config`/`enable`), yaml-language-server, vscode-json-languageserver, conform.nvim (prettier), nvim-lint (`cfn_lint`), Mason (`cfn-lint`).

---

## Background facts (verified during design — do not re-litigate)

- **prettier preserves `!Ref`/`!GetAtt`/`!Sub` short-form tags** (tested: only indentation/whitespace changed). No CFN-specific formatter is needed.
- **conform splits dotted filetypes** (`conform/init.lua` `get_matching_filetype`: `vim.split(ft, ".")`, most-specific-first, falls back to the base component). So `yaml.cloudformation` still triggers the existing `yaml = { 'prettier' }` entry. **`lua/plugins/format.lua`'s `formatters_by_ft` needs no change.**
- **nvim-lint merges linters across dotted components** (`lint.lua` `_resolve_linter_by_ft`: splits on `.`, unions each component's linters). So `linters_by_ft = { cloudformation = { 'cfn_lint' } }` fires on `yaml.cloudformation` with no special-casing.
- **nvim-lint ships a built-in `cfn_lint.lua`** linter. Its registry key is the module name: **`cfn_lint` (underscore)**, because nvim-lint does `require('lint.linters.' .. key)`. Using `cfn-lint` (hyphen) would fail to load. The Mason *package* is still named `cfn-lint`.
- **Schema URL** `https://raw.githubusercontent.com/awslabs/goformation/master/schema/cloudformation.schema.json` returns HTTP 200.
- **`cfn-lint` is a Mason package** (`pkg:pypi/cfn-lint`).
- **`init.lua` wires `config.*` modules at lines 58–65**; the `config.cloudformation` require slots in there (before the `plugins.*` requires so detection is registered early).
- **Tests:** single harness `tests/health.lua`, run via `tests/run.sh` (which sets `NVIM_APPNAME=nvim-dev` and passes `-u`). Green = exit 0, printed `0 failure(s)`. Deferred/LSP-runtime behaviour that a headless run can't exercise live is asserted by **source-grep** of the plugin file, matching the harness's existing style (see its `automatic_enable`, `lazydev`, `mini.pairs` checks).

---

## File structure

- **Create:** `lua/config/cloudformation.lua` — `intrinsic_tags` (data), `schema_url` (data), `is_template(bufnr)` (pure), `setup()` (detection autocmd). One responsibility: "is this buffer a CFN template, and mark it if so."
- **Modify:** `init.lua` — one `require('config.cloudformation').setup()` line at the `config.*` block.
- **Modify:** `lua/plugins/lsp.lua` — `customTags` on `yamlls`; `'cfn-lint'` in `ensure_installed`; a `register_cfn_buffer` helper + `User CloudFormationDetected` autocmd + a hook in the existing `LspAttach` callback to push the schema.
- **Modify:** `lua/plugins/format.lua` — `cloudformation = { 'cfn_lint' }` in `linters_by_ft`.
- **Modify:** `tests/health.lua` — assertions per task.

`lua/plugins/format.lua`'s `formatters_by_ft` is **not** modified (see facts above).

---

## Task 1: `config.cloudformation` data + detection helper

Pure module: intrinsic tags, schema URL, and `is_template`. No plugin deps, so it's assertable directly in the harness.

**Files:**
- Create: `lua/config/cloudformation.lua`
- Test: `tests/health.lua` (new `== cloudformation ==` section, appended before the final `if #failures` block)

- [ ] **Step 1: Write the failing tests**

Insert this block into `tests/health.lua` immediately before the final `if #failures > 0 then` block (around line 624):

```lua
print '== cloudformation =='
local ok_cfn, cfn = pcall(require, 'config.cloudformation')
check('config.cloudformation loads', ok_cfn, tostring(cfn))
if ok_cfn then
  check('cloudformation.intrinsic_tags is a non-empty list', type(cfn.intrinsic_tags) == 'table' and #cfn.intrinsic_tags > 0, tostring(cfn.intrinsic_tags))
  check('cloudformation.schema_url is a string', type(cfn.schema_url) == 'string' and cfn.schema_url:match '^https?://' ~= nil, tostring(cfn.schema_url))
  check('cloudformation.is_template is a function', type(cfn.is_template) == 'function')

  -- intrinsic_tags must cover the tags yaml-language-server would otherwise
  -- reject. A representative sample (both scalar and sequence forms exist for
  -- some, e.g. !Sub); assert the tag names appear somewhere in the list.
  local tag_blob = table.concat(cfn.intrinsic_tags, ' ')
  for _, tag in ipairs { '!Ref', '!GetAtt', '!Sub', '!If', '!Join', '!Select', '!FindInMap', '!ImportValue', '!Equals', '!And', '!Or', '!Not', '!Base64' } do
    check('customTag covers ' .. tag, tag_blob:find(tag, 1, true) ~= nil, 'missing from intrinsic_tags')
  end

  if type(cfn.is_template) == 'function' then
    -- YAML with AWSTemplateFormatVersion -> template.
    local b1 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b1, 0, -1, false, { 'AWSTemplateFormatVersion: "2010-09-09"', 'Resources:', '  B:', '    Type: AWS::S3::Bucket' })
    check('is_template true for AWSTemplateFormatVersion', cfn.is_template(b1) == true)
    vim.api.nvim_buf_delete(b1, { force = true })

    -- YAML with only a top-level Resources: key -> template.
    local b2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { '# a stack', 'Resources:', '  Q:', '    Type: AWS::SQS::Queue' })
    check('is_template true for top-level Resources:', cfn.is_template(b2) == true)
    vim.api.nvim_buf_delete(b2, { force = true })

    -- Ordinary YAML (a CI workflow) -> NOT a template. `jobs:` and a nested
    -- `resources:` under it must not trigger; only a TOP-LEVEL Resources: does.
    local b3 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b3, 0, -1, false, { 'name: CI', 'on: push', 'jobs:', '  build:', '    resources:', '      cpu: 2' })
    check('is_template false for ordinary YAML workflow', cfn.is_template(b3) == false)
    vim.api.nvim_buf_delete(b3, { force = true })

    -- JSON template.
    local b4 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b4, 0, -1, false, { '{', '  "AWSTemplateFormatVersion": "2010-09-09",', '  "Resources": {}', '}' })
    check('is_template true for JSON template', cfn.is_template(b4) == true)
    vim.api.nvim_buf_delete(b4, { force = true })
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — `config.cloudformation loads` fails with a "module not found" message; suite prints a nonzero failure count.

- [ ] **Step 3: Create the module**

Create `lua/config/cloudformation.lua`:

```lua
-- CloudFormation template detection and data.
--
-- Pure data plus one pure predicate (is_template) and one autocmd registrar
-- (setup) -- mirrors lua/config/project.lua so it can be required from
-- lua/plugins/lsp.lua and asserted directly in tests/health.lua.
--
-- Detection is CONTENT-BASED, not filename-based: CFN templates have arbitrary
-- names, so a buffer is a template when it declares AWSTemplateFormatVersion or
-- a TOP-LEVEL Resources: key. On a match the buffer gets a composite filetype
-- (yaml.cloudformation / json.cloudformation): yamlls/jsonls/prettier keep
-- matching the yaml/json component unchanged, while cfn-lint and the schema push
-- target the cloudformation component. See docs/superpowers/specs.

local M = {}

--- yaml-language-server customTags for CFN short-form intrinsic functions.
---
--- Without these, yamlls reports every `!Ref`/`!GetAtt`/... as an unresolved
--- tag. Both scalar and sequence forms are listed where CFN allows both
--- (e.g. `!Sub "..."` vs `!Sub [ "...", { ... } ]`). Harmless in ordinary YAML.
M.intrinsic_tags = {
  '!Ref scalar',
  '!GetAtt scalar',
  '!GetAtt sequence',
  '!Sub scalar',
  '!Sub sequence',
  '!Join sequence',
  '!Select sequence',
  '!Split sequence',
  '!FindInMap sequence',
  '!If sequence',
  '!Equals sequence',
  '!And sequence',
  '!Or sequence',
  '!Not sequence',
  '!Condition scalar',
  '!Base64 scalar',
  '!Base64 mapping',
  '!Cidr sequence',
  '!ImportValue scalar',
  '!ImportValue mapping',
  '!GetAZs scalar',
  '!Transform mapping',
}

--- The CFN JSON schema. goformation maintains a merged schema covering every
--- resource type; yaml-language-server downloads and caches it, so no copy is
--- vendored here. Verified reachable (HTTP 200) at design time.
M.schema_url = 'https://raw.githubusercontent.com/awslabs/goformation/master/schema/cloudformation.schema.json'

--- Returns true if `bufnr`'s contents look like a CloudFormation template.
---
--- Reads a bounded prefix only: templates declare structure at the top, and an
--- unbounded scan would read a huge data file in full. A TOP-LEVEL `Resources:`
--- (YAML) or `"Resources"` (JSON) key, or an AWSTemplateFormatVersion anywhere
--- in the prefix, is the signal. `jobs:` -> nested `resources:` in a CI workflow
--- is deliberately NOT matched, because the key must be at column 0.
---@param bufnr integer
---@return boolean
function M.is_template(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 256, false)
  for _, line in ipairs(lines) do
    if line:find('AWSTemplateFormatVersion', 1, true) then return true end
    -- Top-level YAML mapping key: no leading whitespace.
    if line:match '^Resources%s*:' then return true end
    -- Top-level JSON key: allow the leading brace/whitespace JSON permits.
    if line:match '^%s*"Resources"%s*:' then return true end
  end
  return false
end

return M
```

- [ ] **Step 4: Run to verify it passes**

Run: `tests/run.sh`
Expected: the `== cloudformation ==` checks pass. (The whole suite may still fail on later-task assertions not yet added — that's fine; confirm no `cloudformation`-named failures.)

- [ ] **Step 5: Commit**

```bash
git add lua/config/cloudformation.lua tests/health.lua
git commit -m "feat(cfn): add cloudformation detection module and data"
```

---

## Task 2: Wire detection autocmd + init.lua

Add `setup()` (the `FileType` autocmd that marks CFN buffers) and require it from `init.lua`.

**Files:**
- Modify: `lua/config/cloudformation.lua` (add `setup`)
- Modify: `init.lua:65` (add require)
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing tests**

Add to the `== cloudformation ==` section in `tests/health.lua`, after the existing Task-1 assertions:

```lua
  -- Detection autocmd must be registered by init.lua (own augroup).
  check('cloudformation augroup exists', count_autocmds 'config-cloudformation' > 0, 'setup() not wired from init.lua')

  -- init.lua must actually require the module (see the WIRING vs STATE note near
  -- the top of this file: requiring it here would mask a missing init.lua line).
  local cfn_init = io.open(vim.fn.stdpath 'config' .. '/init.lua', 'r')
  if cfn_init then
    local src = cfn_init:read 'a'
    cfn_init:close()
    check('init.lua sets up config.cloudformation', src:match "require%s*%(?%s*'config%.cloudformation'%s*%)?%s*%.setup" ~= nil or src:match "require%('config%.cloudformation'%)" ~= nil, 'not required in init.lua')
  end

  -- End-to-end: a yaml buffer with template content, run through the detection
  -- callback, gets the composite filetype and the marker variable.
  if type(cfn.setup) == 'function' then
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'AWSTemplateFormatVersion: "2010-09-09"', 'Resources:', '  B: { Type: AWS::S3::Bucket }' })
    vim.api.nvim_buf_set_option(b, 'filetype', 'yaml')
    check('detected buffer filetype is yaml.cloudformation', vim.bo[b].filetype == 'yaml.cloudformation', vim.bo[b].filetype)
    check('detected buffer sets b:cloudformation', vim.b[b].cloudformation == true)
    vim.api.nvim_buf_delete(b, { force = true })

    -- A plain yaml buffer must be left as-is (no recursion, no false positive).
    local b2 = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { 'name: CI', 'jobs:', '  build:', '    steps: []' })
    vim.api.nvim_buf_set_option(b2, 'filetype', 'yaml')
    check('ordinary yaml buffer stays yaml', vim.bo[b2].filetype == 'yaml', vim.bo[b2].filetype)
    vim.api.nvim_buf_delete(b2, { force = true })
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — `cloudformation augroup exists` and the filetype-detection checks fail (`setup` undefined / not wired).

- [ ] **Step 3: Add `setup()` to the module**

Append to `lua/config/cloudformation.lua`, before `return M`:

```lua
--- Registers content-based CFN detection on yaml/json buffers.
---
--- On a matching buffer, sets the composite filetype and `b:cloudformation`,
--- then fires `User CloudFormationDetected` (data = bufnr) so the LSP layer can
--- push the schema without this module depending on it.
function M.setup()
  local group = vim.api.nvim_create_augroup('config-cloudformation', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    desc = 'Detect CloudFormation templates and mark the buffer',
    group = group,
    pattern = { 'yaml', 'json', 'json5' },
    callback = function(args)
      local buf = args.buf
      -- Guard against the re-trigger from setting filetype below, and against
      -- acting on an already-composite filetype.
      if vim.b[buf].cloudformation then return end
      if not M.is_template(buf) then return end

      vim.b[buf].cloudformation = true
      local base = args.match:match 'json' and 'json' or 'yaml'
      vim.bo[buf].filetype = base .. '.cloudformation'

      vim.api.nvim_exec_autocmds('User', { pattern = 'CloudFormationDetected', data = { buf = buf } })
    end,
  })
end
```

- [ ] **Step 4: Wire it in `init.lua`**

In `init.lua`, after the `require 'config.project'` block (line 65), add:

```lua

-- CloudFormation template detection. Marks yaml/json buffers whose CONTENTS are
-- a CFN template with a composite filetype, so lua/plugins/lsp.lua can attach
-- the schema and lua/plugins/format.lua can run cfn-lint. Set up here so the
-- FileType autocmd exists before the first buffer opens.
require('config.cloudformation').setup()
```

- [ ] **Step 5: Run to verify it passes**

Run: `tests/run.sh`
Expected: all `== cloudformation ==` checks pass.

- [ ] **Step 6: Commit**

```bash
git add lua/config/cloudformation.lua init.lua tests/health.lua
git commit -m "feat(cfn): detect templates and set composite filetype"
```

---

## Task 3: Intrinsic tags on yamlls + cfn-lint in Mason

Stop the unresolved-tag errors (the most visible breakage) and ensure `cfn-lint` installs.

**Files:**
- Modify: `lua/plugins/lsp.lua` — `yamlls` entry (line 207) and `ensure_installed` (line ~246)
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing tests**

Add to the `== cloudformation ==` section in `tests/health.lua`:

```lua
  -- yamlls must carry the intrinsic-function customTags, or every !Ref/!GetAtt
  -- in a template is flagged as an unresolved tag.
  local yaml_cfg = server_cfg 'yamlls'
  check('yamlls configured (for cfn tags)', yaml_cfg ~= nil)
  if yaml_cfg then
    local tags = vim.tbl_get(yaml_cfg, 'settings', 'yaml', 'customTags') or {}
    check('yamlls has non-empty customTags', type(tags) == 'table' and #tags > 0, tostring(#tags))
    local blob = table.concat(tags, ' ')
    check('yamlls customTags include !GetAtt', blob:find('!GetAtt', 1, true) ~= nil)
  end

  -- cfn-lint must be in the mason-tool-installer ensure_installed list. The list
  -- is inside a deferred function, so assert the SOURCE (same approach the
  -- harness uses for automatic_enable).
  local cfn_lsp_src = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/lsp.lua', 'r')
  if cfn_lsp_src then
    local src = cfn_lsp_src:read 'a'
    cfn_lsp_src:close()
    check('lsp.lua ensures cfn-lint installed', src:match "'cfn%-lint'" ~= nil, 'not in ensure_installed')
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — `yamlls has non-empty customTags` and `lsp.lua ensures cfn-lint installed` fail.

- [ ] **Step 3: Add customTags and the require**

In `lua/plugins/lsp.lua`, add the require near the top with the other requires (after `local project = require 'config.project'`, line 18):

```lua
local cloudformation = require 'config.cloudformation'
```

Replace the `yamlls = {}` line (line 207) with:

```lua
  -- yaml-language-server. customTags teaches it CFN's short-form intrinsic
  -- functions (!Ref, !GetAtt, !Sub, ...) so a template stops reporting every one
  -- as an unresolved tag. Harmless for ordinary YAML. The CFN *schema* is not set
  -- statically here -- detection is content-based, so lua/config/cloudformation
  -- marks templates and the schema is pushed per-buffer below.
  yamlls = {
    settings = { yaml = { customTags = cloudformation.intrinsic_tags } },
  },
```

- [ ] **Step 4: Add cfn-lint to ensure_installed**

In the `ensure_installed` list (the "Formatters and linters" group, near line 266, after `'markdownlint-cli2',`), add:

```lua
      'cfn-lint',
```

- [ ] **Step 5: Run to verify it passes**

Run: `tests/run.sh`
Expected: the two new checks pass; existing `yamlls configured` check still passes.

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/lsp.lua tests/health.lua
git commit -m "feat(cfn): teach yamlls intrinsic tags, install cfn-lint"
```

---

## Task 4: Runtime schema association

Push the CFN schema to the running `yamlls`/`jsonls` client for each detected buffer, using `workspace/didChangeConfiguration` — the same idiom as the existing `set_python_path`.

**Files:**
- Modify: `lua/plugins/lsp.lua` — add `register_cfn_buffer` + `User` autocmd; call from the existing `LspAttach` callback
- Test: `tests/health.lua` (source-grep, since no LSP client attaches in a headless run)

- [ ] **Step 1: Write the failing tests**

Add to the `== cloudformation ==` section in `tests/health.lua`:

```lua
  -- Schema association runs at LSP runtime, so a headless run has no client to
  -- observe. Assert the SOURCE wires it (same style as the automatic_enable and
  -- rust inlay-hint checks above).
  local cfn_lsp_src2 = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/lsp.lua', 'r')
  if cfn_lsp_src2 then
    local src = cfn_lsp_src2:read 'a'
    cfn_lsp_src2:close()
    check('lsp.lua listens for CloudFormationDetected', src:match 'CloudFormationDetected' ~= nil, 'schema is never associated')
    check('lsp.lua pushes schema via didChangeConfiguration', src:match 'workspace/didChangeConfiguration' ~= nil)
    check('lsp.lua references the cfn schema_url', src:match 'cloudformation%.schema_url' ~= nil or src:match 'schema_url' ~= nil)
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — the three new grep checks fail.

- [ ] **Step 3: Add the register helper and autocmd**

In `lua/plugins/lsp.lua`, add this block just before the final enablement loop (before `-- Single owner of enablement.`, line 458):

```lua
-- CLOUDFORMATION SCHEMA ASSOCIATION.
--
-- Detection is content-based (lua/config/cloudformation), so the schema-to-file
-- association is not known until a buffer is inspected -- a static filename glob
-- in settings.yaml.schemas cannot express "this file, because of its contents".
-- So the schema is pushed at runtime, per detected buffer, via
-- workspace/didChangeConfiguration -- the same mechanism set_python_path uses
-- above.
--
-- A yamlls/jsonls client is shared across every buffer under one root, so the
-- matched paths accumulate and the whole list is re-pushed each time; setting
-- the schemas table directly (not tbl_deep_extend) avoids leaving stale list
-- entries behind.
local cfn_yaml_files, cfn_json_files = {}, {}

---Associates the CFN schema with `buf` on its yamlls/jsonls client, if attached.
---@param buf integer
local function register_cfn_buffer(buf)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.b[buf].cloudformation) then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return end
  local ft = vim.bo[buf].filetype

  if ft:find 'yaml' then
    if not vim.tbl_contains(cfn_yaml_files, name) then cfn_yaml_files[#cfn_yaml_files + 1] = name end
    for _, client in ipairs(vim.lsp.get_clients { name = 'yamlls', bufnr = buf }) do
      client.settings = client.settings or {}
      client.settings.yaml = client.settings.yaml or {}
      client.settings.yaml.schemas = client.settings.yaml.schemas or {}
      client.settings.yaml.schemas[cloudformation.schema_url] = cfn_yaml_files
      client:notify('workspace/didChangeConfiguration', { settings = client.settings })
    end
  elseif ft:find 'json' then
    if not vim.tbl_contains(cfn_json_files, name) then cfn_json_files[#cfn_json_files + 1] = name end
    for _, client in ipairs(vim.lsp.get_clients { name = 'jsonls', bufnr = buf }) do
      client.settings = client.settings or {}
      client.settings.json = client.settings.json or {}
      -- jsonls schemas is a LIST of { url, fileMatch } entries; find or create
      -- ours and refresh its fileMatch.
      local schemas = client.settings.json.schemas or {}
      local entry
      for _, s in ipairs(schemas) do
        if s.url == cloudformation.schema_url then
          entry = s
          break
        end
      end
      if not entry then
        entry = { url = cloudformation.schema_url, fileMatch = {} }
        schemas[#schemas + 1] = entry
      end
      entry.fileMatch = cfn_json_files
      client.settings.json.schemas = schemas
      client:notify('workspace/didChangeConfiguration', { settings = client.settings })
    end
  end
end

-- Detection (FileType) usually fires before the language server attaches, so the
-- push cannot happen at detection time alone. Handle both orders:
--   * client already running (e.g. opening a second template) -> push now;
--   * client attaches later -> the LspAttach callback below re-pushes.
vim.api.nvim_create_autocmd('User', {
  desc = 'Associate the CFN schema when a template is detected',
  pattern = 'CloudFormationDetected',
  group = vim.api.nvim_create_augroup('config-cfn-schema', { clear = true }),
  callback = function(ev) register_cfn_buffer(ev.data.buf) end,
})
```

- [ ] **Step 4: Hook the existing LspAttach callback**

In the `LspAttach` callback in `lua/plugins/lsp.lua`, add near its end (after the inlay-hint block, before the callback's closing `end`, around line 420):

```lua
    -- If this buffer was already marked a CFN template (detection runs on
    -- FileType, before attach), associate the schema now that the client exists.
    if vim.b[buf].cloudformation then register_cfn_buffer(buf) end
```

Note: `register_cfn_buffer` is defined below the `LspAttach` autocmd in file order, but it's referenced inside a callback that only runs at attach time, so the upvalue is resolved by then. (If lint complains about use-before-definition, move the `register_cfn_buffer` definition and the `local cfn_yaml_files, cfn_json_files` above the `LspAttach` autocmd — behaviour is identical.)

- [ ] **Step 5: Run to verify it passes**

Run: `tests/run.sh`
Expected: the three grep checks pass; full suite returns to `0 failure(s)` (all prior tasks green).

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/lsp.lua tests/health.lua
git commit -m "feat(cfn): associate cloudformation schema at LSP runtime"
```

---

## Task 5: cfn-lint via nvim-lint

Wire `cfn_lint` to the `cloudformation` filetype component.

**Files:**
- Modify: `lua/plugins/format.lua:63` (`linters_by_ft`)
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing test**

Add to the `== cloudformation ==` section in `tests/health.lua` (the `lint` module is already required in the harness's `== completion and formatting ==` section, but require it defensively here):

```lua
  local ok_lint, lint_mod = pcall(require, 'lint')
  if ok_lint then
    check('cfn_lint registered for cloudformation ft', lint_mod.linters_by_ft.cloudformation ~= nil and vim.tbl_contains(lint_mod.linters_by_ft.cloudformation, 'cfn_lint'), vim.inspect(lint_mod.linters_by_ft.cloudformation))
    -- The linter definition must resolve. nvim-lint ships lint/linters/cfn_lint;
    -- the registry key is the module name (underscore), NOT the binary name.
    check('cfn_lint linter definition resolves', lint_mod.linters.cfn_lint ~= nil and lint_mod.linters.cfn_lint.cmd == 'cfn-lint', tostring(lint_mod.linters.cfn_lint and lint_mod.linters.cfn_lint.cmd))
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh`
Expected: FAIL — `cfn_lint registered for cloudformation ft` fails (`linters_by_ft.cloudformation` is nil).

- [ ] **Step 3: Add the linter mapping**

In `lua/plugins/format.lua`, replace the `lint.linters_by_ft` line (line 63):

```lua
lint.linters_by_ft = { markdown = { 'markdownlint-cli2' } }
```

with:

```lua
-- cfn_lint keys on the `cloudformation` filetype component
-- (lua/config/cloudformation sets a composite filetype like yaml.cloudformation).
-- nvim-lint splits dotted filetypes and unions each component's linters, so this
-- fires alongside nothing else on the yaml side. The registry key is `cfn_lint`
-- (the module name), NOT the `cfn-lint` binary name.
lint.linters_by_ft = {
  markdown = { 'markdownlint-cli2' },
  cloudformation = { 'cfn_lint' },
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `tests/run.sh`
Expected: both new checks pass; suite is `0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add lua/plugins/format.lua tests/health.lua
git commit -m "feat(cfn): run cfn-lint on cloudformation buffers"
```

---

## Task 6: Full verification + manual smoke test

Confirm the automated suite is green and verify the end-to-end behaviour a headless run can't (needs Mason installs + network).

**Files:** none (verification only)

- [ ] **Step 1: Run the full suite**

Run: `tests/run.sh`
Expected: prints `0 failure(s)` and exits 0.

- [ ] **Step 2: Install the tools**

In a real Neovim session: `:MasonToolsInstall`, wait for `cfn-lint`, `prettier`, `yaml-language-server`, `json-lsp` to report installed (`:Mason` to inspect).

- [ ] **Step 3: Manual YAML template check**

Create `/tmp/cfn-smoke.yaml`:

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "${AWS::StackName}-data"
      Tags:
        - Key: Arn
          Value: !GetAtt MyBucket.Arn
```

Open it and verify:
- `:echo &filetype` → `yaml.cloudformation`
- `:echo b:cloudformation` → `v:true`
- No "unresolved tag" diagnostics on `!Sub` / `!GetAtt` (`:lua vim.diagnostic.open_float()` or read virtual text).
- `:ConformInfo` lists `prettier` as available for the buffer.
- Introduce an error (e.g. `Type: AWS::S3::Bucket` → `Type: AWS::S3::Buckettt`), `:write`, and confirm a `cfn-lint`-sourced diagnostic appears.
- Mangle indentation and add stray spaces, `:write`, and confirm prettier reformats **while leaving `!Sub`/`!GetAtt` intact**.

- [ ] **Step 4: Manual JSON template check**

Create `/tmp/cfn-smoke.json`:

```json
{ "AWSTemplateFormatVersion": "2010-09-09", "Resources": { "B": { "Type": "AWS::S3::Bucket" } } }
```

Open it and verify `:echo &filetype` → `json.cloudformation`, prettier formats on save, and schema completion offers resource properties (insert mode inside `"B": { ... }`, trigger completion).

- [ ] **Step 5: Final commit (if any doc updates)**

If the manual pass reveals a doc-worthy note, update the README's tooling section; otherwise nothing to commit. The feature is complete.

---

## Self-review notes

- **Spec coverage:** intrinsic tags (Task 3), schema completion/validation (Tasks 3+4), cfn-lint (Task 5), formatting-preserves-tags (verified; relies on unchanged conform config — Task 6 confirms), content-based detection (Tasks 1–2), composite filetype (Task 2), new module placement (Task 1), remote schema URL (Task 1 data). All spec sections map to a task.
- **Type/name consistency:** module is `config.cloudformation` throughout; fields `intrinsic_tags`, `schema_url`, `is_template`, `setup`; buffer var `vim.b.cloudformation`; User event `CloudFormationDetected` with `data.buf`; helper `register_cfn_buffer`; nvim-lint key `cfn_lint` (underscore) vs Mason package `cfn-lint` (hyphen) — the one genuinely error-prone naming split, called out at every use site.
- **No placeholders:** every code step is complete and runnable.
```
