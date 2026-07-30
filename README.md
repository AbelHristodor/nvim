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
| `lua/config/` | Options, keymaps, autocmds, diagnostics, Brazil tuning |
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
2. **Keep the Brazil excludes.** `lua/config/brazil.lua` excludes `build/`,
   a cross-volume symlink into the build farm. `find -L ~/workplace` reaches
   **99,186** Python files; the package actually being edited has ~130. (Plain
   `find` reports 0 because `~/workplace` is itself a symlink — which is how the
   original survey undercounted by ~800x.)
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
| `gd` on a Brazil Python file | "takes ages" | 0.3 ms warm, 52 ms cold |
| Startup `require` calls | — | 106 (down from 254 pre-deferral) |

## Keymaps

Leader is `<Space>`. Scheme follows LazyVim conventions.

| Key | Action |
|---|---|
| `gd` / `gr` / `gI` / `gy` | definition / references / implementation / type def |
| `K` | hover (grouped hover actions in Rust) |
| `gK` | toggle diagnostic virtual_lines |
| `<leader>ca` / `cr` / `cf` | code action / rename / format |
| `<leader>ff` / `fg` / `fb` / `fr` | find files / grep / buffers / recent |
| `<leader>e` / `-` | file explorer (float) / parent directory |
| `<leader>gg` | lazygit |
| `<leader>uf` / `uF` | toggle format-on-save global / buffer |
| `]d` / `[d` / `]e` / `[e` | next/prev diagnostic, next/prev error |
| `]h` / `[h` | next / previous git hunk |
| `<leader>d*` / `<leader>t*` | debug / test |
| `<C-h/j/k/l>` | window navigation |
