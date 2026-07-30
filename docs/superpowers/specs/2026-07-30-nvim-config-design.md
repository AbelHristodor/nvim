# Neovim config design — fast, hand-rolled, kickstart-based

Date: 2026-07-30
Status: approved, ready for implementation planning

## Problem

`gd` on a Python function takes several seconds. The working assumption was
"LazyVim is bloated." Measurement says otherwise: there are two causes, and
neither is distro bloat.

### Cause 1: reference-counting codelens on cursor movement

`lensline.nvim`, configured in the user's own
`~/.config/nvim/lua/plugins/lensline.lua`:

- `lensline/setup.lua:90` — triggers on `CursorMoved` and `CursorMovedI`
- `lensline/config.lua:93` — `debounce_ms = 500`
- `lensline/config.lua:4-19` — default providers are `usages`
  (`include = { "refs" }`) and `last_author`

Every ~500ms of cursor movement it issues a `textDocument/references` request
for every function visible in the buffer. Pyright resolves find-references by
walking the whole workspace and services requests on a single-threaded queue.
A `textDocument/definition` request therefore waits behind a backlog of
whole-workspace reference scans. This is head-of-line blocking.

### Cause 2: Brazil `build/` symlinks indexed by pyright

Each Brazil package contains a `build/` symlink pointing into the build farm on
a separate volume, e.g.

```
~/workplace/PanoramaMCP/src/PanoramaMCP/build
  -> /Users/abelor/workplace/PanoramaMCP/build/PanoramaMCP/PanoramaMCP-0.1/AL2_x86_64/DEV.STD.PTHREAD/build
```

That tree contains 2,558 Python files. Pyright follows the symlink and indexes
them, paying cross-volume I/O for files that are build output.

Only 2 of ~36 packages carry a `pyrightconfig.json` that excludes it
(`~/workplace/PPdev/src/PPdev` and `.../PPdevCore`). Those files already list
`"exclude": ["build", ...]`, indicating someone hit this and fixed it locally.

### Cause 3 (separate, smaller): startup time

Startup on an empty buffer measures 170–280ms across runs.

```
264.670  109.381: require('config.lazy')
 53.632   25.886: require('codecompanion.providers')
 27.746    4.222: require('cmp')
```

`~/.config/nvim/lua/config/lazy.lua:22` sets `defaults = { lazy = false }`, so
LazyVim's own plugins lazy-load but the user's plugins (codecompanion, mcphub,
render-markdown) load eagerly. `checker.enabled = true` adds periodic git
update checks. 37 extras are enabled, including Java, Kotlin, Ruby, SQL,
Tailwind, Terraform and cmake; `jdtls` and `kotlin-language-server` are
installed in Mason.

### Scope note

Fixing causes 1 and 2 would speed up `gd` in the existing LazyVim install. The
rebuild is justified by startup time, config readability, and dropping ~20
unused language extras — not by the `gd` fix. Both fixes are carried into the
new config regardless.

## Environment (verified)

| Item | Value |
|---|---|
| Neovim | 0.12.0 (LuaJIT 2.1) |
| `vim.pack` | present (`vim.pack.add` is a function) |
| `vim.lsp.config` / `vim.lsp.enable` | both present |
| Terminal font | FiraCode Nerd Font (wezterm + iTerm2) |
| Present | rust-analyzer, ruff, pyright, node 20, cargo, go, rg, fd, fzf, lazygit, mise, uv, bun, gcc, dot |
| Missing (Mason installs) | basedpyright, prettier, taplo, delve |

Language mix by file count in actual work (`~/workplace/*/src`):
Python 124, TypeScript 85 + TSX 5, Smithy 54, Rust 8, Ruby 2.
Build markers: 36 `Config`, 14 `package.json`, 11 `setup.py`,
10 `pyproject.toml`, 3 `Cargo.toml`.

`git rev-parse --show-toplevel` inside a Brazil package returns the package
directory, not the workspace — each package is its own repo. LSP root detection
therefore lands on the package naturally.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Plugin manager | `vim.pack` | Built into 0.12, no bootstrap, no manager in the startup path. Upstream kickstart has migrated to it, so this repo stays mergeable with upstream. |
| Repo strategy | Build here, symlink when ready | Test via `NVIM_APPNAME=nvim-dev`; `~/.config/nvim` stays untouched until cutover. LazyVim remains a fallback. |
| Python LSP | basedpyright + ruff | Proven navigation engine; ruff for lint/format. The `exclude` tuning is what fixes `gd`. |
| Keymaps | LazyVim-style | `keymaps.lua` is empty, so muscle memory is on LazyVim defaults. Swap the engine, not the controls. |
| Picker | fzf-lua | Native fzf binary present at `~/.fzf/bin/fzf`; fastest on large repos. |
| Extras | DAP, neotest, gitsigns + lazygit | AI (codecompanion/mcphub) dropped — 26ms of startup, not wanted. |
| Brazil handling | Global excludes in config | Works in all ~36 packages with no per-repo files. |
| Smithy | Treesitter + filetype only | 54 files justify highlighting; no JVM server, keeps config portable. |
| Diagnostics | Hybrid virtual_text + virtual_lines | Researched below. |
| Format on save | On, with toggle | Brazil packages vary in convention, so a toggle is needed. |

### Diagnostics research

Sources: Neovim 0.12 `:help diagnostic` (read locally from
`/opt/homebrew/Cellar/neovim/0.12.0/share/nvim/runtime/doc/diagnostic.txt`),
PR neovim/neovim#31959, LazyVim and kickstart current defaults.

`virtual_lines` landed in Neovim 0.11 (PR #31959, Jan 2025) as an upstream port
of `lsp_lines.nvim`, relicensed for core by its author. The plugin is therefore
obsolete; the feature is built in.

Neovim 0.12 defaults every display handler off except `underline`:

```
{ signs = "boolean", underline = true, virtual_lines = false, virtual_text = false }
```

Both distros still ship the pre-0.11 configuration:

- LazyVim (`lua/lazyvim/plugins/lsp/init.lua:16-35`): `virtual_text` with
  `prefix = "●"`, `source = "if_many"`, no `virtual_lines`
- kickstart: `virtual_text = true`, `virtual_lines = false`, commented
  "Can switch between these as you prefer"

The docs themselves promote a hybrid via two named examples:

- `*diagnostic-on-jump-example*` (diagnostic.txt:194-208) — on jump, show
  `{ virtual_lines = { current_line = true }, virtual_text = false }`
- `*diagnostic-toggle-virtual-lines-example*` (diagnostic.txt:180-188) — a `gK`
  keymap toggling `virtual_lines`

`current_line` on `virtual_text` is three-state (diagnostic.txt:728-733):
`true` = only the cursor line, `false` = all lines **except** the cursor line,
`nil` = all lines. The `false` value exists specifically to compose with
`virtual_lines`.

Chosen configuration:

```lua
virtual_text  = { current_line = false, source = 'if_many', prefix = '●' }
virtual_lines = { current_line = true }
```

Compact markers everywhere; the cursor line expands to readable multi-line
detail. This suits long Rust and TypeScript type errors, which virtual text
truncates.

Performance: PR #31959 contains no performance discussion — no benchmarks, no
large-file caveats. These handlers render extmarks over the visible viewport and
issue **no LSP requests**. Diagnostics are pushed by the server via
`textDocument/publishDiagnostics` and are already in memory. This is
categorically unlike codelens, which pulls per symbol.

Accepted tradeoff: text below the cursor line shifts as the cursor moves
vertically. `gK` toggles it off; changing the default is a one-line edit.

## Architecture

Split the current single 990-line `init.lua` into focused modules.

```
init.lua                    -- leader, vim.pack build hooks, module requires in order
lua/config/options.lua      -- vim.o settings
lua/config/keymaps.lua      -- non-plugin keymaps (LazyVim-style)
lua/config/autocmds.lua     -- yank highlight, etc.
lua/config/diagnostics.lua  -- hybrid virtual_text/virtual_lines, gK, on_jump
lua/plugins/ui.lua          -- tokyonight, lualine, which-key, mini.*, todo-comments
lua/plugins/picker.lua      -- fzf-lua + find keymaps
lua/plugins/treesitter.lua  -- parsers, smithy filetype registration
lua/plugins/lsp.lua         -- mason, lspconfig, servers, LspAttach keymaps
lua/plugins/completion.lua  -- blink.cmp + LuaSnip
lua/plugins/format.lua      -- conform.nvim
lua/plugins/git.lua         -- gitsigns + lazygit
lua/plugins/dap.lua         -- nvim-dap + dap-ui
lua/plugins/test.lua        -- neotest (pytest adapter; Rust via rustaceanvim)
lua/plugins/rust.lua        -- rustaceanvim (vim.g.rustaceanvim only, no setup())
lua/lang/brazil.lua         -- root markers, build/ excludes
after/ftplugin/rust.lua     -- rustaceanvim keymaps
```

`vim.g.have_nerd_font = true` (FiraCode Nerd Font verified in both terminals).

### Lazy-loading model

`vim.pack.add` is eager; deferral is opt-in via `packadd` inside autocmds. This
inverts lazy.nvim's model, so keeping the plugin count low is a performance
decision rather than tidiness. Filetype-scoped plugins (rustaceanvim, neotest
adapters) self-defer and cost ~0ms until the relevant filetype opens.

## Language support

| Language | LSP | Format | Lint |
|---|---|---|---|
| Python | basedpyright + ruff | ruff | ruff |
| TypeScript/TSX | vtsls | prettier | eslint if configured |
| Rust | rustaceanvim / rust-analyzer | rustfmt | clippy |
| Lua | lua_ls | stylua | — |
| Go | gopls | gofumpt + goimports | — |
| Bash | bashls | shfmt | shellcheck |
| JSON / YAML / TOML | jsonls, yamlls, taplo | prettier / taplo | — |
| Markdown | marksman | prettier | markdownlint (MD013 disabled) |
| Smithy | none | — | — |

Dropped from the current 37 extras: Java, Kotlin, Ruby, SQL, Tailwind,
Terraform, cmake, clangd, docker, nvim-cmp, codecompanion, mcphub, lensline.

### Python

```lua
basedpyright = {
  settings = { basedpyright = { analysis = {
    diagnosticMode = 'openFilesOnly',
    exclude = { '**/build', '**/.bemol', '**/node_modules', '**/__pycache__',
                '**/target', '**/.venv', '**/env', '**/dist', '**/.tox',
                '**/.mypy_cache' },
    useLibraryCodeForTypes = true,
  }}},
}
```

`ruff` runs alongside for lint and organize-imports, with its hover capability
disabled so basedpyright remains the single source for hover and navigation.

Root markers pinned to `{ 'pyproject.toml', 'setup.py', 'Config', '.git' }` so
each server's scope is one Brazil package.

`pyright` remains installed as a fallback if basedpyright misbehaves on Brazil
layouts.

### TypeScript

`vtsls`, with the performance settings from its README:

- `vtsls.experimental.completion.enableServerSideFuzzyMatch = true`
- `vtsls.experimental.completion.entriesLimit` capped
- `typescript.preferences.includePackageJsonAutoImports = 'off'`
- `typescript.tsserver.maxTsServerMemory = 8192`

### Rust

`mrcjkb/rustaceanvim`, pinned to major 9 (latest release v9.0.5; v9 requires
Neovim 0.12, which this environment has). Its README lists `vim.pack` first
among install methods with the recommended range `vim.version.range('^9')`.

```lua
vim.pack.add {
  { src = 'https://github.com/mrcjkb/rustaceanvim', version = vim.version.range '^9' },
}
```

Constraints from its README:

- No `setup()` call. Configuration goes in `vim.g.rustaceanvim`, set before the
  plugin initializes — explicitly **not** in `after/ftplugin/rust.lua`, which
  loads after initialization. Keymaps do go there.
- It owns `rust_analyzer` exclusively; also running the lspconfig
  `rust_analyzer` setup "may cause conflicts."

Therefore `rust_analyzer` must never be enabled by this config or by
mason-lspconfig. See "Server enablement: exactly one owner" below.

mason-lspconfig's own docs use `exclude = { "rust_analyzer", "ts_ls" }` as their
example, since these are the servers commonly managed by dedicated plugins.

### Server enablement: exactly one owner

Read from
`~/.local/share/nvim/lazy/mason-lspconfig.nvim/lua/mason-lspconfig/features/automatic_enable.lua`:
`enable_server` calls **both** `vim.lsp.config(lspconfig_name, config)` and
`vim.lsp.enable(lspconfig_name)`, where `config` comes from
`mason-lspconfig.lsp.<server>` when that module exists. Its `exclude` handling
(lines 22-36) behaves as documented.

Current kickstart `init.lua:773-776` also loops over its own server table
calling `vim.lsp.config` then `vim.lsp.enable`. Keeping both mechanisms would
double-configure every server, and mason-lspconfig's bundled per-server
overrides could displace the tuned settings — including the basedpyright
`exclude` patterns that are the entire point of this work.

Resolution: **this config owns enablement.** Set
`automatic_enable = false` and enable servers explicitly:

```lua
require('mason-lspconfig').setup { automatic_enable = false }

for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
  vim.lsp.enable(name)
end
-- rust_analyzer is absent from `servers`; rustaceanvim owns it.
```

mason-lspconfig is retained only for `ensure_installed` and the name mapping
between lspconfig names and Mason package names (e.g. `lua_ls` <->
`lua-language-server`). `rust_analyzer` is simply not present in the `servers`
table, so no `exclude` list is needed and there is one unambiguous owner per
server.

Verification criterion 6 covers this: `rust_analyzer` must start exactly once.

It provides grouped code actions (which `vim.lsp.buf.code_action` cannot
render), `runnables`/`debuggables`/`testables`, hover actions, `expandMacro`,
`explainError`, `flyCheck`, `openCargo`/`openDocs`, `crateGraph` (needs `dot`,
present), and a built-in neotest adapter with automatic DAP detection.

### Picker

fzf-lua with profile `{ 'default-title', 'fzf-native' }`, using the native fzf
binary. `lsp.jump1 = true` (already its default, `defaults.lua:1429`) makes `gd`
jump directly when there is a single result, with no picker flash.

fzf-lua has no hard lazy.nvim dependency — the single reference in
`lua/fzf-lua/actions.lua:786` is guarded by `if ... package.loaded.lazy then`,
so it is an optional integration and works under `vim.pack`.

## Hard rule: no codelens

No `lensline.nvim`, no `vim.lsp.codelens`, no reference-counting virtual text.
Any feature that issues `textDocument/references` or
`textDocument/implementation` on cursor movement reintroduces cause 1.

Distinction to preserve: server-**pushed** data (diagnostics) is free to render;
client-**pulled** per-symbol data (codelens) competes with foreground
navigation for the same single-threaded server.

## Keymaps (LazyVim-style)

| Key | Action |
|---|---|
| `gd` / `gr` / `gI` / `gy` | definition / references / implementation / type definition |
| `K` | hover |
| `<leader>ca` / `cr` / `cf` | code action / rename / format |
| `<leader>ff` / `fg` / `fb` / `fr` | find files / grep / buffers / recent |
| `<leader>e` | file explorer |
| `<leader>gg` | lazygit |
| `<leader>uf` / `uF` | toggle format-on-save global / buffer |
| `]d` / `[d` | next / previous diagnostic (shows virtual_lines on jump) |
| `gK` | toggle diagnostic virtual_lines |
| `<C-h/j/k/l>` | window navigation |

## Formatting

conform.nvim, format-on-save enabled for python (ruff), rust (rustfmt),
ts/tsx/json (prettier), lua (stylua), sh (shfmt), toml (taplo).
`<leader>uf` toggles globally, `<leader>uF` per buffer.

## Verification

Test the new config in isolation:

```
NVIM_APPNAME=nvim-dev
```

with `~/.config/nvim-dev` symlinked to this repo. `~/.config/nvim` is not
modified. Note that `NVIM_APPNAME` also isolates the data directory
(`~/.local/share/nvim-dev`), so Mason installs do not collide with existing
LazyVim state. Nothing is deleted.

Acceptance criteria:

1. `nvim --startuptime` — baseline 170–280ms; target under 60ms
2. Timed `gd` on a Python function in `~/workplace/Qualo/src/Qualo` — the
   original complaint, measured rather than assumed
3. `:checkhealth` clean
4. A real edit in each of Python, TypeScript, Rust and Lua: completion, hover,
   `gd`, rename, format-on-save
5. Diagnostics render as designed: compact markers off-cursor, virtual lines on
   the cursor line, `gK` toggles
6. Rust: `rust_analyzer` starts exactly once (no double-enable), runnables and
   neotest work

Cutover to `~/.config/nvim` happens only on explicit approval.

## Out of scope

- Amazon `smithy-language-server` (filetype and highlighting only)
- AI plugins (codecompanion, mcphub) — dropped by decision
- Generating `pyrightconfig.json` into work repos — excludes live in the nvim
  config instead
- Migrating LazyVim's `lua/config/*.lua` — those files are empty
