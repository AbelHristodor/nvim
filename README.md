# Neovim config

Fast, modular Neovim config for Python, TypeScript, Rust, Go, Lua, Bash and
friends. Built on Neovim 0.12's built-in `vim.pack` plugin manager — no
lazy.nvim, no bootstrap code.

Originally derived from kickstart.nvim; now restructured into focused modules.

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

Everything is installed and updated through Neovim 0.12's built-in `vim.pack` —
there is no plugin-manager dependency. Inspect state with
`:lua vim.pack.update(nil, { offline = true })`; update with
`:lua vim.pack.update()` (`:write` applies, `:quit` cancels).

Theme is **catppuccin macchiato**. The **picker is telescope** with the native C
sorter; the **file tree is nvim-tree**; lists are **trouble.nvim**; completion is
**blink.cmp**. Rust is handled by **rustaceanvim** (which owns `rust_analyzer`
exclusively — see the notes below).

| Concern | Plugins | File |
|---|---|---|
| Colorscheme / UI | `catppuccin`, `lualine.nvim`, `mini.icons` | `plugins/ui.lua` |
| Editing utilities | `mini.ai`, `mini.surround`, `mini.pairs`, `mini.indentscope` | `plugins/ui.lua` |
| Keymap hints / TODOs / lists | `which-key.nvim`, `todo-comments.nvim`, `trouble.nvim` | `plugins/ui.lua` |
| QoL / sessions / replace | `snacks.nvim`, `persistence.nvim`, `grug-far.nvim` | `plugins/editor.lua` |
| Fuzzy finder | `telescope.nvim`, `telescope-fzf-native.nvim`, `telescope-ui-select.nvim`, `plenary.nvim` | `plugins/picker.lua` |
| LSP | `nvim-lspconfig`, `mason.nvim`, `mason-lspconfig.nvim`, `mason-tool-installer.nvim`, `fidget.nvim`, `lazydev.nvim` | `plugins/lsp.lua` |
| Completion / snippets | `blink.cmp`, `LuaSnip`, `friendly-snippets` | `plugins/completion.lua` |
| Format / lint | `conform.nvim`, `nvim-lint` | `plugins/format.lua` |
| Treesitter | `nvim-treesitter` (main), `nvim-treesitter-textobjects` (main) | `plugins/treesitter.lua` |
| File tree | `nvim-tree.lua` | `plugins/explorer.lua` |
| Git | `gitsigns.nvim`, `diffview.nvim` (+ lazygit terminal) | `plugins/git.lua` |
| Pinned files | `harpoon` (branch `harpoon2`, telescope UI) | `plugins/harpoon.lua` |
| Rust | `rustaceanvim` | `plugins/rust.lua` |
| Debugging | `nvim-dap`, `nvim-dap-ui`, `nvim-dap-virtual-text`, `nvim-dap-python`, `nvim-nio` | `plugins/dap.lua` |
| Testing | `neotest`, `neotest-python`, `FixCursorHold.nvim`, `nvim-nio` | `plugins/test.lua` |

`mini.nvim` is installed as a single repo; the individual `mini.*` modules above
are set up from it. `snacks.nvim` uses six modules — `bigfile`, `quickfile`,
`notifier`, `input`, `words` and `gitbrowse` (see the performance notes in
`plugins/editor.lua` for why the rest are off). `words` owns LSP reference
highlighting (`]]` / `[[` navigation), replacing the manual `documentHighlight`
autocmd that used to live in `plugins/lsp.lua`.

### Language tooling

Servers, formatters, linters and debug adapters are installed on demand via
`mason-tool-installer` (run `:MasonToolsInstall`).

| Kind | Tools |
|---|---|
| LSP servers | `basedpyright` + `ruff` (Python), `vtsls` (TS/JS), `lua_ls`, `gopls`, `bashls`, `jsonls`, `yamlls`, `taplo`, `marksman` |
| Rust LSP | `rust_analyzer` — owned by rustaceanvim, not lspconfig |
| Formatters | `stylua`, `ruff`, `rustfmt`, `prettier`, `shfmt`, `gofumpt`, `goimports`, `taplo` |
| Linters | `shellcheck` (via bashls), `markdownlint-cli2` (via nvim-lint) |
| Debug adapters | `debugpy` (Python), `codelldb` (Rust) |

## Keymaps

Leader is `<Space>`. **Find, grep, search, git and LSP keys mirror LazyVim
key-for-key** so muscle memory transfers. Keymaps live in three layers: global
(`lua/config/keymaps.lua`), buffer-local on `LspAttach` (`lua/plugins/lsp.lua`),
and filetype-local (`after/ftplugin/rust.lua`).

### LSP (buffer-local, on attach)

| Key | Mode | Action |
|---|---|---|
| `gd` | n | Goto definition |
| `gr` | n | References |
| `gI` | n | Goto implementation |
| `gy` | n | Goto type definition |
| `gD` | n | Goto declaration |
| `K` | n | Hover (grouped hover *actions* in Rust) |
| `gK` | n | Signature help |
| `<C-k>` | i | Signature help |
| `<leader>cr` | n | Rename |
| `<leader>ca` | n, x | Code action (grouped in Rust) |
| `<leader>cs` | n | Document symbols |
| `<leader>cS` | n | Workspace symbols |
| `<leader>cf` | n, v | Format buffer |
| `<leader>cd` | n | Line diagnostics (float) |
| `<leader>uh` | n | Toggle inlay hints (on by default in Rust only) |
| `]]` / `[[` | n, t | Next / previous reference to symbol under cursor (snacks.words) |

### Find / files (`<leader>f`, telescope)

| Key | Action |
|---|---|
| `<leader>ff` / `<leader><space>` | Find files (root dir) |
| `<leader>fg` | Find files (**git-files**, not grep) |
| `<leader>fb` / `<leader>fB` | Buffers (MRU) / buffers (all) |
| `<leader>fr` | Recent files |
| `<leader>fc` | Find config file |
| `<leader>fe` / `<leader>fE` | Explorer (root dir / cwd) |

### Search / grep (`<leader>s`, telescope)

| Key | Action |
|---|---|
| `<leader>/` / `<leader>sg` | Live grep (root dir) — both, as in LazyVim |
| `<leader>sw` | Grep word (normal) / selection (visual) |
| `<leader>sb` | Buffer lines |
| `<leader>sd` / `<leader>sD` | Workspace / buffer diagnostics |
| `<leader>sc` / `<leader>sC` | Command history / commands |
| `<leader>s/` | Search history |
| `<leader>sa` | Auto commands |
| `<leader>sh` / `<leader>sH` | Help pages / highlight groups |
| `<leader>sj` / `<leader>sm` | Jumplist / marks |
| `<leader>sk` | Keymaps |
| `<leader>sl` / `<leader>sq` | Location list / quickfix list |
| `<leader>sM` | Man pages |
| `<leader>sR` | Resume last picker |
| `<leader>sr` | Project-wide search & replace (grug-far) |
| `<leader>:` | Command history |

### Git (`<leader>g`)

| Key | Action |
|---|---|
| `<leader>gs` | Status (telescope) |
| `<leader>gc` / `<leader>gl` | Commits (telescope) |
| `<leader>gS` | Stash (telescope) |
| `<leader>gg` | Lazygit (floating terminal) |
| `<leader>gB` | Git browse — open line/selection on the remote (n, x) |
| `<leader>gd` / `<leader>gD` | Diff view open / close (diffview) |
| `<leader>gf` / `<leader>gF` | File history — current file / whole repo (diffview) |
| `<leader>ghs` / `<leader>ghr` | Stage / reset hunk (gitsigns) |
| `<leader>ghp` / `<leader>ghb` | Preview hunk / blame line |
| `<leader>ghd` | Diff this |
| `]h` / `[h` | Next / previous hunk |

### Harpoon (`<leader>h`)

Pin the handful of files you actively switch between; the list persists per
project root. The menu is rendered through telescope; press `<C-d>` inside it to
drop the selected entry.

| Key | Action |
|---|---|
| `<leader>ha` | Add current file to the list |
| `<leader>hh` | Open the list (telescope) |
| `<leader>hm` | Open the built-in quick menu |
| `<leader>hn` / `<leader>hp` | Next / previous file in the list |
| `<leader>h1`–`<leader>h5` | Jump to list slot 1–5 |

### Diagnostics & lists (`<leader>x`, trouble)

| Key | Action |
|---|---|
| `<leader>xx` / `<leader>xX` | Diagnostics / buffer diagnostics (Trouble) |
| `<leader>xt` | Todo (Trouble) |
| `<leader>xL` / `<leader>xQ` | Location / quickfix list (Trouble) |
| `<leader>xq` / `<leader>xl` | Quickfix / location list (native `copen`/`lopen`) |
| `<leader>cs` / `<leader>cS` | Symbols / LSP refs (Trouble; also LSP pickers above) |

### UI toggles (`<leader>u`)

| Key | Action |
|---|---|
| `<leader>ud` | Toggle diagnostic virtual_lines |
| `<leader>uh` | Toggle inlay hints (Rust only, on by default) |
| `<leader>uf` / `<leader>uF` | Toggle format-on-save global / buffer |
| `<leader>un` | Dismiss notifications |
| `<leader>uC` | Colorscheme with preview |
| `<leader>n` | Notification history |

### Sessions (`<leader>q`, persistence)

| Key | Action |
|---|---|
| `<leader>qs` / `<leader>qS` | Restore / select session |
| `<leader>ql` / `<leader>qd` | Restore last / stop saving session |

### Debug (`<leader>d`, nvim-dap)

| Key | Action |
|---|---|
| `<leader>db` / `<leader>dB` | Toggle / conditional breakpoint |
| `<leader>dc` | Continue |
| `<leader>di` / `<leader>do` / `<leader>dO` | Step into / over / out |
| `<leader>dr` / `<leader>du` | Toggle REPL / debug UI |
| `<leader>dt` | Terminate |

### Test (`<leader>t`, neotest)

| Key | Action |
|---|---|
| `<leader>tt` / `<leader>tf` | Run nearest / file tests |
| `<leader>tl` / `<leader>td` | Run last / debug nearest |
| `<leader>ts` / `<leader>to` | Toggle summary / show output |
| `<leader>tS` | Stop test run |

### Rust (`after/ftplugin/rust.lua`, buffer-local)

| Key | Action |
|---|---|
| `K` | Hover actions (grouped) |
| `<leader>ca` | Code action (grouped) |
| `<leader>cR` / `<leader>cD` | Runnables / debuggables |
| `<leader>ce` / `<leader>cm` | Explain error / expand macro |
| `<leader>cp` | Parent module |
| `<leader>cC` / `<leader>cdo` | Open Cargo.toml / docs.rs |

### Textobjects & motion (treesitter)

| Key | Action |
|---|---|
| `am` / `im` | Function outer / inner (x, o) |
| `ac` / `ic` | Class outer / inner (x, o) |
| `a=` / `i=` | Assignment outer / inner (x, o) |
| `]m` / `[m` | Next / previous function start |
| `]M` / `[M` | Next / previous function end |
| `]c` / `[c` | Next / previous class |
| `]a` / `[a` | Swap parameter forward / back |

`mini.ai` also adds `va)`, `vi"`, `ci'`, `aa`/`ii` (next), `af`/`if` (function
*call*), etc.; `mini.surround` adds `sa`/`sd`/`sr` (add/delete/replace
surroundings).

### Bracket navigation

| Key | Action |
|---|---|
| `]d` / `[d` | Next / previous diagnostic |
| `]e` / `[e` | Next / previous error |
| `]h` / `[h` | Next / previous git hunk |
| `]t` / `[t` | Next / previous todo comment |
| `]q` / `[q` | Next / previous quickfix item |
| `]b` / `[b` | Next / previous buffer |

### Windows, buffers, editing (global)

| Key | Mode | Action |
|---|---|---|
| `<C-h/j/k/l>` | n | Window navigation |
| `<C-Up/Down/Left/Right>` | n | Resize window |
| `<S-h>` / `<S-l>` | n | Previous / next buffer |
| `<leader>bd` / `<leader>bo` | n | Delete buffer / delete other buffers |
| `<A-j>` / `<A-k>` | n, v | Move line/selection down / up |
| `<C-d>` / `<C-u>` | n | Half-page down / up (centred) |
| `n` / `N` | n | Next / previous search result (centred) |
| `<` / `>` | v | Indent left / right (keep selection) |
| `<C-s>` | i, x, n, s | Save file |
| `<Esc>` | n | Clear search highlight |
| `<Esc><Esc>` | t | Exit terminal mode |
| `<leader>e` / `<leader>E` | n | File tree sidebar (root dir / cwd) |
| `<leader>cv` | n | Select Python interpreter (`:VenvSelect`) |

Three deliberate departures from LazyVim:

* **`<leader>ud`** holds the diagnostic virtual_lines toggle. Neovim's docs put it
  on `gK`, but LazyVim uses `gK` for signature help and that binding wins.
* **No `<leader>cc` / `cC`** (run/refresh codelens). Codelens is deliberately
  absent — see the performance notes.
* **Textobjects use `am`/`im` and `ac`/`ic`**, the treesitter-textobjects
  upstream scheme, rather than LazyVim's `af`/`if`. `f` is already mini.ai's
  function-*call* textobject, so the upstream keys keep both without a remap.

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

Telescope's LSP pickers jump straight to a lone result rather than opening a
menu, so `gd` stays a direct jump — `tests/health.lua` asserts the config never
sets `jump_type = 'never'`, which would break that.

## Measurements

| | Before (LazyVim) | After |
|---|---|---|
| Startup (median) | 167–277 ms | ~94 ms |
| `gd` (cross-file, Python) | "takes ages" | 0.3 ms warm, 52 ms cold |
| Startup `require` calls | — | 106 (down from 254 pre-deferral) |

## Tests

```bash
ln -sfn "$PWD" ~/.config/nvim-dev   # once
tests/run.sh                        # health + startup + gd latency
```

The suite runs under `NVIM_APPNAME=nvim-dev`, so it cannot disturb a real config
or its plugin state. Note `tests/run.sh` passes `-u` deliberately: `nvim -l`
skips user config without it, which would make every assertion vacuous.
