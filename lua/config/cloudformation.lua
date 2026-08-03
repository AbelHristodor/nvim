-- CloudFormation template detection and data.
--
-- Pure data plus one pure predicate (is_template) -- mirrors
-- lua/config/project.lua so it can be required from lua/plugins/lsp.lua and
-- asserted directly in tests/health.lua. A later change adds a detection
-- autocmd that consumes this data.
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
    -- Top-level JSON key: allow the leading whitespace pretty-printed JSON puts
    -- before the key (the "Resources" key sits one indent level in).
    if line:match '^%s*"Resources"%s*:' then return true end
  end
  return false
end

return M
