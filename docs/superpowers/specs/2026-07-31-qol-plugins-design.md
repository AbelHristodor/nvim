# Quality-of-life plugin additions

Date: 2026-07-31

Adds the quality-of-life layer this config was missing, measured against the
most-installed Neovim plugins (dotfyle top 25) and LazyVim's defaults. Every
addition is either a genuine gap or a fix for a gap the research surfaced.

The binding constraint is the startup budget asserted by `tests/startup.lua`:
**125 ms**, currently met at 95.5 ms median. Nothing here may push past that.

## Startup budget

| | ms |
|---|---|
| Current median | 95.5 |
| snacks.nvim (measured cold, 3 runs: 5.50 / 4.40 / 4.34) | +4.4 |
| lazydev (gated to `FileType lua`) | ~+1 |
| Everything else (keymap- or event-triggered) | 0 |
| **Projected** | **~102** |
| Budget | 125 |

Only snacks and lazydev are eager. All other additions use the deferral pattern
already documented in `lua/plugins/completion.lua`: do not call `vim.pack.add`
until first use, because `{ load = false }` still lands the plugin on
runtimepath and Neovim sources its `plugin/` files later in the same startup.

## Additions

### 1. snacks.nvim — bigfile, quickfile, notifier, input

Scope deliberately limited to four modules. Rejected: `picker` and `explorer`
(duplicate telescope and nvim-tree), `statuscolumn` and `dashboard` (cosmetic),
`scroll` and `words` (per-motion and per-CursorHold work; `words` duplicates the
existing `documentHighlight` autocmd in `lsp.lua`), `indent` (see §2).

**This is the one new eager plugin, and it cannot be deferred.** `bigfile` hooks
`BufReadPre` and `quickfile` exists specifically to render a file *before*
plugins load; deferring either defeats its purpose. Affordable because
`Snacks.setup()` only registers autocmds — every submodule sits behind an
`__index` metatable that requires on demand. Verified in its `init.lua`:
`setup()` builds one augroup with a `once` autocmd per event group. Measured
cost 4.4 ms / 4 modules.

`bigfile` closes a real gap: this config has no large-file guard, so opening a
generated file starts treesitter and an LSP over it.

Two user-visible changes, both accepted:

- `notifier` replaces `vim.notify`. The ~8 existing call sites (`VenvSelect`,
  format toggles, lazygit) become stacked auto-dismissing popups instead of
  `:messages` lines. History on `<leader>n`, dismiss on `<leader>un`.
- `input` replaces `vim.ui.input`. No conflict with the telescope `ui-select`
  extension: `vim.ui.input` and `vim.ui.select` are separate hooks.

### 2. mini.indentscope — indent guides

Chosen over `snacks.indent`; enabling both would draw overlapping extmarks in
the same columns and flicker. mini.nvim is already on disk and eagerly loaded,
so this costs one `setup()` call and no download.

Disabled in the buffer types where guides are noise (help, terminal, trouble,
nvim-tree, dashboard, checkhealth, lazygit, gitcommit).

### 3. mini.pairs — autopairing

The largest genuine gap found: #16 most-installed (1197 configs) and this config
has no autopairing at all. Already on disk.

**`<CR>` is safe to leave to mini.pairs, contrary to the usual warning.**
Verified empirically rather than assumed. blink.cmp's `default` preset does
*not* map `<CR>` — it accepts on `<C-y>`, mirroring built-in ins-completion
(consistent with the comment in `completion.lua`). Probed live: with blink
loaded, `maparg('<CR>', 'i')` is empty, and mini.pairs then installs
`v:lua.MiniPairs.cr()`. mini.pairs also guards this itself — it only maps `<CR>`
when `maparg('<CR>', mode) == ''` (its `pairs.lua:557`), so it yields to any
future binding.

Keeping it is desirable: `MiniPairs.cr()` is what puts the cursor on a properly
indented blank line when you press Enter between `{` and `}`.

Set `modes = { insert = true, command = true, terminal = false }` — command mode
added so pairs work on the `:` line; terminal left off so they never interfere
with a shell or lazygit.

Borrows LazyVim's tuning: skip pairing before an alphanumeric/quote character,
skip inside treesitter `string` nodes, detect unbalanced pairs, and
`markdown = true` for fenced code blocks.

### 4. nvim-treesitter-textobjects — function and class textobjects

`mini.ai`'s builtin set (verified in its source, `H.builtin_textobjects`) is
`( [ { < ' " ` ? a b f t q`, where `f` is function *call*, not function
*definition*. So there is currently no way to select a whole function body or a
class. This is why treesitter-textobjects is #20 most-installed.

Prerequisite confirmed: nvim-treesitter's `main` branch ships **no**
`textobjects.scm` (0 files found across all languages), but the companion repo
carries its own queries. Present for every language in use — rust (15
function/class captures), python, lua, go, typescript. Its default branch is
already `main`, matching the nvim-treesitter pin in `treesitter.lua`.

**Keys use the upstream scheme, not LazyVim's.** `am`/`im` for functions
(m = method), `ac`/`ic` for classes. This leaves `mini.ai`'s `f`
(function-call) untouched and needs no remap. Movement: `]m`/`[m` between
functions, `]c`/`[c` between classes, `]a` parameter swap.

**Map conflict, and why the README's advice is too blunt.** Neovim's own
`ftplugin/python.vim` maps `]m`/`[m` buffer-locally in n/o/x modes (lines
64-83), which would shadow the global maps in the most-used language here. The
README suggests `vim.g.no_plugin_maps = true`, but that disables ftplugin maps
across all 29 filetypes that honour it. Set only the per-filetype flags for the
languages affected in practice: `vim.g.no_python_maps` and
`vim.g.no_ruby_maps`.

### 5. lazydev.nvim — Lua API completion for this config

Relevant because this repo *is* a 2000-line Neovim config. Gives on-demand
`vim.*` types and completion. The existing `lua_ls.on_init` runtime-library scan
stays (it serves a different purpose — workspace libraries); lazydev loads types
per-require, which is strictly better for config editing.

Gated to `FileType lua`, so it costs nothing when editing anything else. It
pushes `workspace/didChangeConfiguration` to already-running clients (its
`lsp.lua:92`), so it works whether it loads before or after `lua_ls` starts.

### 6. persistence.nvim — session management

Nothing currently saves buffer or window layout. Chosen over `mini.sessions`
(which is on disk) because it matches LazyVim's `<leader>q*` keymaps, preserving
the muscle memory this config deliberately mirrors everywhere else, and because
it autosaves on `VimLeavePre` rather than requiring a manual save.

Note `persistence.setup()` calls `M.start()` internally, which registers the
`VimLeavePre` autosave — so setup must run for autosave to work, but it is
triggered lazily on the first `<leader>q*` press. Accepted trade-off: a session
is only saved if you touched a session keymap during that Neovim run.

Keys: `<leader>qs` restore, `<leader>qS` select, `<leader>ql` restore last,
`<leader>qd` stop saving.

### 7. grug-far.nvim — project-wide search and replace

Telescope greps but cannot replace across files. `<leader>sr`, matching LazyVim.
Fully deferred to first keypress.

### 8. Bracket navigation keymaps

Zero-cost keymaps filling gaps in the existing `]d`/`]e`/`]h` set:

- `]t`/`[t` — todo comments, via `todo-comments`' `jump_next`/`jump_prev`
  (confirmed exported at its `init.lua:21-22`). Must load todo-comments first,
  which is already deferred behind `BufReadPost`.
- `]q`/`[q` — quickfix, with `pcall` so it reports "no more items" instead of
  throwing at the end of the list.
- `]b`/`[b` — buffer cycling, complementing the existing `<S-h>`/`<S-l>`.

### 9. Cleanup

Five stale plugin directories are on disk but absent from the config, left over
from the pre-telescope migration: `fzf-lua`, `oil.nvim`, `tokyonight.nvim`,
`guess-indent.nvim`, and a bare `nvim` directory. Harmless (not on runtimepath
unless added) but removed with `vim.pack.del` for tidiness.

`FixCursorHold.nvim` is **kept**. An earlier read of the research called it
unreferenced; it is in fact a declared neotest dependency at `test.lua:15`,
deferred with the rest of the neotest stack. It is obsolete for Neovim 0.12, but
removing a working test dependency is out of scope here.

## File layout

New file `lua/plugins/editor.lua` holds the QoL layer, keeping `ui.lua` focused
on appearance. It owns snacks, mini.pairs, mini.indentscope, persistence and
grug-far.

| File | Change |
|---|---|
| `lua/plugins/editor.lua` | new — snacks, mini.pairs, mini.indentscope, persistence, grug-far |
| `lua/plugins/lsp.lua` | add lazydev, gated to `FileType lua` |
| `lua/plugins/treesitter.lua` | add nvim-treesitter-textobjects + select/move/swap keymaps |
| `lua/config/keymaps.lua` | `]t`/`[t`, `]q`/`[q`, `]b`/`[b` |
| `lua/config/health.lua` | `:checkhealth config` assertions |
| `init.lua` | require `plugins.editor` |
| `tests/health.lua` | one assertion per addition |
| `README.md` | keymap table and plugin set |

## Testing

Extend `tests/health.lua` with an assertion per addition. Each new assertion
must be shown to **fail without its fix** before being accepted — the same
verification applied to the Rust inlay hints change, which caught that a
`vim.g`-based assertion could pass vacuously.

Specific invariants worth asserting:

- `mini.pairs` owns `<CR>` in insert mode, and blink still accepts on `<C-y>`
  (guards the interaction documented in §3 against a future blink preset change)
- indent guides have exactly one owner (mini.indentscope on, snacks.indent off)
- `vim.g.no_python_maps` is set (otherwise `]m` silently does the wrong thing
  in Python)
- snacks is configured with only the four intended modules
- startup stays under budget — `tests/startup.lua` already enforces this and is
  the real regression gate for the whole change
