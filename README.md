# Neovim config

Fast, modular Neovim config for Python, TypeScript, Rust, Go, Lua, Bash and
friends. Built on Neovim 0.12's built-in `vim.pack` plugin manager — no
lazy.nvim, no bootstrap code.

Originally derived from kickstart.nvim; now restructured into focused modules.

Design and rationale: `docs/superpowers/specs/2026-07-30-nvim-config-design.md`
Implementation plan: `docs/superpowers/plans/2026-07-30-nvim-config.md`

## Requirements

Neovim >= 0.12, git, make, a C compiler, `rg`, `fd`, `fzf`, a Nerd Font.
Optional: `lazygit`, `cargo`, `go`, `node`.

## Layout

| Path | Contents |
|---|---|
| `init.lua` | Leader keys, `PackChanged` build hooks, module requires |
| `lua/config/` | Options, keymaps, autocmds, diagnostics, project detection |
| `lua/plugins/` | One file per concern |
| `after/ftplugin/` | Filetype-local keymaps |
| `tests/` | Headless test suite |

## Plugins

`:lua vim.pack.update(nil, { offline = true })` inspects state;
`:lua vim.pack.update()` updates (`:write` applies, `:quit` cancels).

## Tests

```bash
ln -sfn "$PWD" ~/.config/nvim-dev   # once
tests/run.sh                        # health + startup + gd latency
```

The suite runs under `NVIM_APPNAME=nvim-dev`, so it cannot disturb a real config
or its plugin state. Note `tests/run.sh` passes `-u` deliberately: `nvim -l`
skips user config without it, which would make every assertion vacuous.

## Performance notes

Three things must not be reintroduced. All were measured, not guessed.

1. **No reference-counting codelens.** Anything issuing
   `textDocument/references` on `CursorMoved` puts whole-workspace scans ahead
   of your definition requests on a single-threaded server. This was the primary
   cause of multi-second `gd` latency in the previous config.
2. **Keep the exclude globs.** `lua/config/project.lua` excludes generated trees
   like `build/`, which is often a symlink onto another volume and can dwarf the
   real source — one measured checkout reached ~99k reachable `.py` files versus
   ~130 actually being edited. Exclusions must cover generated output only:
   excluding `.venv` once hid every third-party import and produced
   "Import could not be resolved" across an entire project.
3. **Lazy-load new plugins.** `vim.pack.add` is eager. Critically,
   `{ load = false }` is *not* enough: it defers sourcing at add-time but still
   puts the plugin on `runtimepath`, so Neovim sources its `plugin/` files later
   in the same startup. Measured with blink.cmp: `init.lua` finished at 119ms,
   blink's `plugin/` file was sourced at 135ms regardless. To genuinely defer,
   don't call `vim.pack.add` until first use — it's idempotent, so calling it
   from a lazy hook is safe. See `lua/plugins/completion.lua` for the pattern.

Only one component may own each language server. `lua/plugins/lsp.lua` owns all
of them except `rust_analyzer`, which belongs to rustaceanvim; this is why
`mason-lspconfig`'s `automatic_enable` is `false`.

## Measurements

| | Before (LazyVim) | After |
|---|---|---|
| Startup (median) | 167–277 ms | ~94 ms |
| `gd` (cross-file, Python) | "takes ages" | 0.3 ms warm, 52 ms cold |
| Startup `require` calls | — | 106 (down from 254 pre-deferral) |

## Keymaps

Leader is `<Space>`. **Find, grep, search, git and LSP keys mirror LazyVim
key-for-key** (taken from its own fzf-lua extra) so muscle memory transfers.

| Key | Action |
|---|---|
| `gd` / `gr` / `gI` / `gy` / `gD` | definition / references / implementation / type def / declaration |
| `K` | hover (grouped hover actions in Rust) |
| `gK` / `<C-k>` (insert) | signature help |
| `<leader>ff` / `<leader><space>` | find files (root dir) |
| `<leader>fg` | find files (**git-files**, not grep) |
| `<leader>fb` / `fB` / `fr` / `fc` | buffers / all buffers / recent / config file |
| `<leader>/` and `<leader>sg` | **grep** (root dir) — both, as in LazyVim |
| `<leader>sw` | grep word (normal) / selection (visual) |
| `<leader>sd` / `sD` | workspace / buffer diagnostics |
| `<leader>sc` / `sC` | command history / commands |
| `<leader>sR` | resume last picker |
| `<leader>sh` / `sk` / `sb` / `sj` / `sm` / `sq` / `sl` | help / keymaps / buffer lines / jumps / marks / quickfix / loclist |
| `<leader>ca` / `cr` / `cf` | code action / rename / format |
| `<leader>gs` / `gc` / `gd` / `gS` | git status / commits / diff hunks / stash |
| `<leader>gg` | lazygit |
| `<leader>e` / `<leader>E` | file tree sidebar (root dir / cwd) |
| `<leader>cv` | select Python interpreter (`:VenvSelect`) |
| `<leader>ud` | toggle diagnostic virtual_lines |
| `<leader>uh` | toggle inlay hints (on by default in Rust only) |
| `<leader>uf` / `uF` | toggle format-on-save global / buffer |
| `]d` / `[d` / `]e` / `[e` | next/prev diagnostic, next/prev error |
| `]h` / `[h` | next / previous git hunk |
| `<leader>xx` / `xX` / `xt` | diagnostics / buffer diagnostics / todo (Trouble) |
| `<leader>cs` / `cS` | symbols / LSP refs (Trouble) |
| `<leader>d*` / `<leader>t*` | debug / test |
| `<C-h/j/k/l>` | window navigation |

Two deliberate departures from LazyVim:

* **`<leader>ud`** holds the diagnostic virtual_lines toggle. Neovim's docs put it
  on `gK`, but LazyVim uses `gK` for signature help and that binding wins.
* **No `<leader>cc` / `cC`** (run/refresh codelens). Codelens is deliberately
  absent — see the performance notes above.

## Python interpreters

The interpreter is auto-detected per project, in this order:

1. `$VIRTUAL_ENV` — an activated venv
2. `<project>/.venv`, then `<project>/venv`
3. a venv declared by the project's `pyrightconfig.json` (`venvPath` + `venv`)

If imports show as unresolved or "unknown symbol", check what the server is
actually using with **`:VenvCurrent`**, then switch with **`:VenvSelect`**
(`<leader>cv`). That pushes the new interpreter to the running server via
`workspace/didChangeConfiguration` — no restart needed — and also updates
`$VIRTUAL_ENV`/`PATH` so terminals, tests and the debugger agree with the LSP.

Detection happens once when the server starts, so a venv activated *after*
opening Neovim needs `:VenvSelect` (or `:LspRestart`). Two gotchas worth knowing:

* A project's own `pyrightconfig.json` **overrides** what the editor sends. If it
  pins a stale `venvPath`, fix or remove that line — no editor setting can win
  against it.
* basedpyright falls back to whatever `python3` is on `PATH`. If that interpreter
  happens to have your packages installed, imports resolve *anyway* and the
  misconfiguration stays hidden until you hit a package it lacks.

## Plugin set

Theme is **catppuccin macchiato**. Picker is **telescope** with the native C
sorter (`telescope-fzf-native`, built by the `PackChanged` hook — without it the
Lua sorter is slow on large repos). File tree is **nvim-tree** on `<leader>e`.
Lists are **trouble.nvim**. Also: gitsigns, mini.ai/surround/icons, lualine,
which-key, todo-comments, treesitter, blink.cmp, conform, nvim-lint,
rustaceanvim, nvim-dap, neotest.

Telescope's LSP pickers jump straight to a lone result rather than opening a
menu, so `gd` stays a direct jump — `tests/health.lua` asserts the config never
sets `jump_type = 'never'`, which would break that.
