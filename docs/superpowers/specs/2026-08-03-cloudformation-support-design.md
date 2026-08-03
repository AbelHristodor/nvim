# CloudFormation template support

Date: 2026-08-03

## Goal

Make this Neovim config first-class for AWS CloudFormation (CFN) templates in
both YAML and JSON, with correct formatting on save. Concretely, a CFN template
should:

- format on save with prettier, preserving short-form intrinsic tags
  (`!Ref`, `!GetAtt`, `!Sub`, ...) untouched;
- not report spurious "unresolved tag" errors on those intrinsic tags;
- get schema-driven completion and validation of resource types and properties;
- get deep, AWS-standard linting via `cfn-lint`.

## Background: what already exists

The config already enables `yamlls` and `jsonls` (`lua/plugins/lsp.lua`) and
already formats `yaml`, `json`, and `jsonc` with prettier
(`lua/plugins/format.lua`). So the base editing experience for these files
works. What is missing is the CFN-specific layer.

Three gaps, in order of how visible they are:

1. **Intrinsic tags.** `yaml-language-server` does not know about CFN's
   short-form tags (`!Ref`, `!GetAtt`, `!Sub`, `!If`, `!Join`, ...). Without
   being told, it flags every one as an unresolved-tag error. This is the most
   visible breakage today.
2. **Schema.** No CFN JSON schema is associated, so there is no completion or
   validation of resource types and their properties.
3. **Deep linting.** A JSON schema cannot catch everything (bad intrinsic
   arguments, invalid property combinations, unresolved refs). `cfn-lint` is the
   AWS-standard checker for that.

## Verified assumption: prettier preserves intrinsic tags

The user's request centers on "proper formatting", so the load-bearing
assumption — that reusing the existing prettier setup is safe for CFN — was
tested empirically before this design was accepted.

Input (deliberately mis-indented `MyRef` block):

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
  MyRef:
     Value:    !Ref MyBucket
```

`prettier --parser yaml` output:

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
  MyRef:
    Value: !Ref MyBucket
```

`!Sub`, `!GetAtt`, and `!Ref` are preserved exactly; only indentation and stray
whitespace are corrected. Therefore no CFN-specific formatter is needed —
prettier, which the config already uses for YAML/JSON, is correct.

## Design decisions (locked)

- **Detection: content-based.** Sniff the buffer for CFN markers rather than
  matching filenames. Templates have arbitrary names, and content sniffing has
  effectively no false positives.
- **Tooling: schema + `cfn-lint`.** Schema for completion/validation, `cfn-lint`
  for deep checks.
- **Formatting: prettier, same as YAML/JSON.** Verified above. No new formatter.
- **Detection module: new `lua/config/cloudformation.lua`.** Matches the
  config's "one file, one clear purpose" convention (mirrors
  `lua/config/project.lua`): pure-ish helpers plus the detection autocmd,
  requirable and testable in isolation.
- **Schema source: remote URL, cached by yaml-language-server.** Point
  `yamlls`/`jsonls` at the CFN JSON schema URL and let the server download and
  cache it. Zero maintenance and always current; first use needs network, which
  is acceptable.

## Mechanism: composite filetype

On detecting a CFN template, the buffer's filetype is set to a **composite**:
`yaml.cloudformation` for YAML, `json.cloudformation` for JSON.

Vim matches each dot-separated component independently, which is exactly the
property this design relies on:

- `yamlls` / `jsonls` / prettier all key on the `yaml` / `json` component, so
  they continue to work unchanged — no special-casing.
- `cfn-lint` and any CFN-specific behaviour key on the `cloudformation`
  component.

A buffer variable `vim.b.cloudformation = true` is also set as a convenient,
explicit flag for the schema-push logic and for tests.

## Components

### A. `lua/config/cloudformation.lua` (new)

Pure data + detection, no plugin dependencies.

- `M.intrinsic_tags` — the list of `customTags` entries yaml-language-server
  needs (`!Ref scalar`, `!GetAtt sequence`, `!GetAtt scalar`, `!Sub sequence`,
  `!Sub scalar`, `!If sequence`, `!Join sequence`, `!Select sequence`,
  `!Split sequence`, `!FindInMap sequence`, `!Base64 scalar/mapping`,
  `!Cidr sequence`, `!ImportValue scalar`, `!GetAZs scalar`,
  `!Condition scalar`, `!And/!Or/!Not/!Equals sequence`, `!Transform mapping`).
  Note both scalar and sequence forms are listed where CFN allows both (e.g.
  `!Sub "..."` vs `!Sub [ "...", { ... } ]`).
- `M.schema_url` — the CFN JSON schema URL
  (`https://raw.githubusercontent.com/awslabs/goformation/master/schema/cloudformation.schema.json`,
  the goformation-maintained schema; confirmed reachable at implementation
  time, otherwise fall back to the SchemaStore CFN schema).
- `M.is_template(bufnr)` — reads a bounded prefix of the buffer (first ~256
  lines is plenty; templates declare structure at the top) and returns true if
  it finds `AWSTemplateFormatVersion` **or** a top-level `Resources:` key. For
  JSON, the equivalent `"AWSTemplateFormatVersion"` / top-level `"Resources"`.
  Bounded read so a huge data file is never scanned in full.
- `M.setup()` — creates a `FileType` autocmd (own augroup, `clear = true`) on
  `yaml`, `json`, `json5`. On match, if `is_template(buf)`, set the composite
  filetype and `vim.b.cloudformation = true`, then fire a `User`
  `CloudFormationDetected` autocmd carrying the bufnr so the LSP layer can react
  without this module depending on it.

Called once from `init.lua` alongside the other `config.*` requires.

Edge case: setting `filetype` re-triggers `FileType`. The autocmd guards with
`vim.b.cloudformation` so it does not recurse, and only acts when the primary
component is still plain `yaml`/`json`.

### B & C. `lua/plugins/lsp.lua` (edit)

**Intrinsic tags (static).** Add `settings.yaml.customTags = require('config.cloudformation').intrinsic_tags`
to the existing `yamlls = {}` entry. This is unconditional — the tags are
harmless in ordinary YAML and this keeps the fix simple.

**Schema (per-buffer, runtime).** Add a `User CloudFormationDetected` autocmd
that pushes the CFN schema to the already-running `yamlls` (or `jsonls`) client
for that buffer via `workspace/didChangeConfiguration`, associating
`M.schema_url` with the buffer's URI. This reuses the exact runtime-config
pattern the file already uses for Python interpreter switching
(`set_python_path`), so it introduces no new idiom. If the relevant client is
not yet attached, the autocmd also runs the association on the next
`LspAttach` for that buffer.

Rationale for runtime push over static `settings.yaml.schemas`: detection is
content-based, so the schema-to-file association is not known until the buffer
is inspected. A static filename-glob association cannot express "this file,
because of its contents".

### D. `lua/plugins/format.lua` (edit)

Add `cfn-lint` to nvim-lint keyed on the `cloudformation` filetype:

```lua
lint.linters_by_ft = {
  markdown = { 'markdownlint-cli2' },
  cloudformation = { 'cfn-lint' },
}
```

nvim-lint looks up linters by the buffer's filetype. Because the composite is
`yaml.cloudformation`, confirm nvim-lint resolves the `cloudformation`
component; if it matches only the full string, the `try_lint` autocmd callback
will pass the `cloudformation` name explicitly for CFN buffers. The existing
`BufWritePost`/`BufReadPost`/`InsertLeave` lint autocmd already covers when it
runs; no new trigger needed.

### E. `lua/plugins/lsp.lua` mason-tool-installer (edit)

Add `'cfn-lint'` to the `ensure_installed` list (verified present in the Mason
registry under that name).

## Formatting

No change to `lua/plugins/format.lua`'s `formatters_by_ft`. conform.nvim splits
dotted filetypes and runs formatters for each component, so `yaml.cloudformation`
still triggers the existing `yaml = { 'prettier' }` entry (and
`json.cloudformation` triggers `json`). Verified prettier behaviour above means
this is correct as-is.

## Testing

`tests/health.lua` is the existing smoke test. Add assertions that:

1. `require('config.cloudformation')` loads and exposes `intrinsic_tags` (non-empty),
   `schema_url` (string), and `is_template`.
2. `is_template` returns true for a YAML buffer containing
   `AWSTemplateFormatVersion`, true for one with a top-level `Resources:`, and
   false for an ordinary YAML doc (e.g. a GitHub Actions workflow with `jobs:`
   but no `Resources:`/format version).
3. After detection, a scratch buffer's filetype is `yaml.cloudformation` and
   `vim.b.cloudformation` is true.
4. `yamlls` config carries a non-empty `customTags`.

Manual verification (documented, not automated — needs Mason installs + network):
open a `.yaml` CFN template, confirm no unresolved-tag diagnostics, confirm
`:ConformInfo` shows prettier, confirm `cfn-lint` diagnostics appear, confirm
save preserves `!Ref`-style tags.

## Non-goals

- SAM/`serverless.yml`-specific transforms and schemas (the `!Transform` /
  `AWS::Serverless-*` world). The generic CFN schema covers the common case;
  SAM support can be a later, separate change.
- A dedicated CFN treesitter parser — none is needed; the `yaml`/`json` parsers
  already highlight these files.
- `cfn-lint` as a language server (it can run in `--lsp` mode). nvim-lint is the
  established pattern in this config for CLI-only linters (see markdownlint), so
  CFN follows it.

## Files touched

- `lua/config/cloudformation.lua` — new
- `init.lua` — one `require('config.cloudformation').setup()` line
- `lua/plugins/lsp.lua` — customTags on yamlls; schema-push autocmd; `cfn-lint`
  in ensure_installed
- `lua/plugins/format.lua` — `cfn-lint` in `linters_by_ft`
- `tests/health.lua` — assertions above
