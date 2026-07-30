# Fast Neovim Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace a 990-line single-file kickstart config with a modular, fast Neovim config supporting Python, TypeScript, Rust, Lua, Go, Bash, JSON/YAML/TOML and Markdown, fixing the two measured causes of `gd` latency.

**Architecture:** Neovim 0.12's built-in `vim.pack` manager (no lazy.nvim). `init.lua` sets the leader, registers `PackChanged` build hooks, then requires focused modules from `lua/config/` and `lua/plugins/`. Each module owns one responsibility and calls `vim.pack.add` for its own plugins. Exactly one component owns each LSP server: `lua/plugins/lsp.lua` for everything except `rust_analyzer`, which rustaceanvim owns exclusively.

**Tech Stack:** Neovim 0.12, `vim.pack`, mason.nvim, nvim-lspconfig, basedpyright, ruff, vtsls, rustaceanvim ^9, nvim-treesitter (main branch), blink.cmp, conform.nvim, fzf-lua, oil.nvim, gitsigns, nvim-dap, neotest, which-key, tokyonight, mini.nvim.

**Spec:** `docs/superpowers/specs/2026-07-30-nvim-config-design.md`

---

## Testing approach (read this before Task 1)

There is no `busted` or `luarocks` on this machine and Lua config code is mostly
declarative, so unit-testing every file would be theatre. Instead this plan uses
a **real assertion harness** that was verified to work:

```
nvim --headless -u ~/.config/nvim-dev/init.lua -l tests/<name>.lua
```

**The `-u` flag is mandatory and is the whole trick.** `:help -l` states: "Skips
user |config| unless |-u| was given." Without `-u`, `nvim -l` runs the script
against a bare Neovim and `init.lua` never executes — every assertion about
options, keymaps or plugins would fail for the wrong reason, and the suite would
be measuring nothing. This was verified directly: with a config setting
`vim.g.__init_lua_ran = true`, plain `-l` reported `nil` and `-u <init.lua> -l`
reported `true`.

`vim.cmd('cq {n}')` propagates the exit code. Verified, capturing nvim's own
status rather than a pipeline's: `cq 1` → `exit=1`, `cq 0` → `exit=0`, and an
uncaught `error()` → `exit=1`. So a test can genuinely fail and be seen to fail.

Plugins also load correctly under `-u ... -l`: `vim.o.loadplugins` is `true`,
`packadd` works, `require` on a plugin module succeeds, and each plugin's
`plugin/` directory is sourced. Verified with a synthetic package.

Three kinds of test are used, each with real teeth:

1. **`tests/health.lua`** — asserts the config loads with zero errors and that
   the expected plugins, servers and keymaps are actually present. Run against
   the real config (not `--clean`).
2. **`tests/startup.lua`** — parses `--startuptime` output and fails if total
   startup exceeds a threshold.
3. **`tests/gd_latency.lua`** — opens a real Brazil Python file, waits for
   basedpyright to attach, then times a `textDocument/definition` round trip
   with `vim.uv.hrtime()`. Fails if it exceeds a threshold. **This is the test
   that proves the user's original complaint is fixed.**

**Isolation.** Every test runs under `NVIM_APPNAME=nvim-dev`. This was verified
to redirect both directories:

```
CONFIG=/Users/abelor/.config/nvim-probe
DATA=/Users/abelor/.local/share/nvim-probe
```

so Mason installs land in `~/.local/share/nvim-dev` and cannot touch the
existing LazyVim state in `~/.local/share/nvim`. `~/.config/nvim` is a real
directory (not a symlink) and is **not modified by any task in this plan**.
Cutover is Task 16 and requires explicit user approval.

**Baseline to beat** (measured on the existing LazyVim install): startup
170–280ms.

---

## File structure

| Path | Responsibility |
|---|---|
| `init.lua` | Leader keys, `vim.loader`, `PackChanged` build hooks, module requires in dependency order |
| `lua/config/options.lua` | `vim.o` / `vim.opt` settings only |
| `lua/config/keymaps.lua` | Non-plugin, non-LSP keymaps |
| `lua/config/autocmds.lua` | Yank highlight, last-position restore, filetype registration |
| `lua/config/diagnostics.lua` | Hybrid `virtual_text`/`virtual_lines`, `gK` toggle, `on_jump` |
| `lua/config/brazil.lua` | Amazon-specific: exclude globs, root markers (data only, no side effects) |
| `lua/plugins/ui.lua` | tokyonight, which-key, lualine, mini.icons/ai/surround, todo-comments |
| `lua/plugins/picker.lua` | fzf-lua + find keymaps |
| `lua/plugins/explorer.lua` | oil.nvim + `<leader>e` / `-` |
| `lua/plugins/treesitter.lua` | Parser install/attach, Smithy filetype |
| `lua/plugins/lsp.lua` | mason, lspconfig, server table, `LspAttach` keymaps, enablement |
| `lua/plugins/completion.lua` | blink.cmp + LuaSnip |
| `lua/plugins/format.lua` | conform.nvim + format-on-save toggle, nvim-lint (markdownlint) |
| `lua/plugins/git.lua` | gitsigns + lazygit |
| `lua/plugins/rust.lua` | rustaceanvim (`vim.g.rustaceanvim` only, no `setup()`) |
| `lua/plugins/dap.lua` | nvim-dap + dap-ui |
| `lua/plugins/test.lua` | neotest + pytest adapter |
| `after/ftplugin/rust.lua` | rustaceanvim-specific keymaps |
| `.markdownlint-cli2.yaml` | markdownlint rules (MD013 disabled) |
| `tests/health.lua` | Config-loads + presence assertions |
| `tests/startup.lua` | Startup time regression gate |
| `tests/gd_latency.lua` | `gd` round-trip latency gate |
| `tests/run.sh` | Runs all three under `NVIM_APPNAME=nvim-dev` |

Files removed: `lua/kickstart/plugins/*.lua` (6 example files), `lua/custom/plugins/init.lua`.
`lua/kickstart/health.lua` is kept and extended (Task 15).

---

## Task 1: Test harness and dev isolation

**Files:**
- Create: `tests/run.sh`
- Create: `tests/health.lua`

- [ ] **Step 1: Create the dev symlink so the config can be tested without touching `~/.config/nvim`**

```bash
ln -sfn /Users/abelor/projects/nvim ~/.config/nvim-dev
readlink ~/.config/nvim-dev
```

Expected output: `/Users/abelor/projects/nvim`

Verify the real config is untouched:

```bash
ls -ld ~/.config/nvim
```

Expected: a real directory, not a symlink.

- [ ] **Step 2: Write the failing test**

Create `tests/health.lua`:

```lua
-- Health assertions for the config. Run via tests/run.sh, which supplies the
-- mandatory -u flag:
--   NVIM_APPNAME=nvim-dev nvim --headless -u ~/.config/nvim-dev/init.lua -l tests/health.lua
-- Exits 0 when all checks pass, 1 otherwise.

local failures = {}

---@param name string
---@param ok boolean
---@param msg? string
local function check(name, ok, msg)
  if ok then
    print(('  ok   %s'):format(name))
  else
    failures[#failures + 1] = name
    print(('  FAIL %s%s'):format(name, msg and (': ' .. msg) or ''))
  end
end

print('== environment ==')
-- has('nvim-0.12') rather than vim.version.ge(): semver ranks a prerelease
-- below its release, so ge(0.12.0-dev, 0.12) is false on nightly builds even
-- though they have the 0.12 APIs this config needs. Verified empirically.
check('neovim >= 0.12', vim.fn.has 'nvim-0.12' == 1, tostring(vim.version()))
check('vim.pack available', type(vim.pack) == 'table' and type(vim.pack.add) == 'function',
  ('vim.pack=%s add=%s'):format(type(vim.pack), type(vim.pack) == 'table' and type(vim.pack.add) or 'n/a'))
check('vim.lsp.config available', type(vim.lsp.config) == 'table' or type(vim.lsp.config) == 'function',
  ('type=%s'):format(type(vim.lsp.config)))
check('running under nvim-dev', vim.fn.stdpath('config'):match('nvim%-dev') ~= nil, vim.fn.stdpath 'config')

-- HARNESS SELF-CHECK. `nvim -l` skips user config unless -u is given, so
-- without it init.lua never runs and every check below would pass or fail for
-- the wrong reason. `vim.g.config_sentinel` is set by the first line of the new
-- init.lua (Task 2); its absence means the suite is testing nothing.
--
-- Expect this to fail until Task 2 replaces init.lua. That is the intended red
-- state, not a broken harness.
check('init.lua ran (harness wired correctly)', vim.g.config_sentinel == true, 'sentinel missing -- run via tests/run.sh, or init.lua not yet rewritten (Task 2)')

print('== modules load ==')
for _, mod in ipairs {
  'config.options',
  'config.keymaps',
  'config.autocmds',
  'config.diagnostics',
  'config.brazil',
} do
  local ok, err = pcall(require, mod)
  check('require ' .. mod, ok, tostring(err))
end

if #failures > 0 then
  print(('\n%d failure(s): %s'):format(#failures, table.concat(failures, ', ')))
else
  print '\n0 failure(s)'
end
vim.cmd(#failures == 0 and 'cq 0' or 'cq 1')
```

- [ ] **Step 3: Create the runner**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# Runs the config test suite in isolation from the user's real config.
# Usage: tests/run.sh [health|startup|gd]
set -uo pipefail

export NVIM_APPNAME=nvim-dev
# -P resolves symlinks, so REPO is a physical path. This MUST match how LINKED
# is computed below: a logical path here would false-mismatch whenever run.sh is
# invoked through a symlink -- including via ~/.config/nvim-dev itself.
REPO="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if [ ! -L "$HOME/.config/nvim-dev" ] || [ ! -d "$HOME/.config/nvim-dev" ]; then
  echo "ERROR: ~/.config/nvim-dev is not a symlink to a directory. Run:"
  echo "  ln -sfn $REPO ~/.config/nvim-dev"
  exit 1
fi

# Assert the symlink points HERE. Existence alone is not enough: a stale link
# would silently run these tests against a different checkout's config.
LINKED="$(cd -P "$HOME/.config/nvim-dev" && pwd)"
if [ "$LINKED" != "$REPO" ]; then
  echo "ERROR: ~/.config/nvim-dev -> $LINKED, but tests live in $REPO"
  echo "Point the symlink at this checkout:"
  echo "  ln -sfn '$REPO' ~/.config/nvim-dev"
  exit 1
fi

rc=0
run_one() {
  local name="$1" script="$2"
  echo "=== $name ==="
  # -u is REQUIRED: `nvim -l` skips user config unless -u is given (:help -l),
  # so without it init.lua never runs and every assertion is meaningless.
  if nvim --headless -u "$HOME/.config/nvim-dev/init.lua" -l "$script"; then
    echo "--- $name PASSED"
  else
    echo "--- $name FAILED"
    rc=1
  fi
  echo
}

case "${1:-all}" in
  health)  run_one health  tests/health.lua ;;
  startup) run_one startup tests/startup.lua ;;
  gd)      run_one gd      tests/gd_latency.lua ;;
  all)
    run_one health tests/health.lua
    [ -f tests/startup.lua ]   && run_one startup tests/startup.lua
    [ -f tests/gd_latency.lua ] && run_one gd tests/gd_latency.lua
    ;;
  *) echo "usage: tests/run.sh [health|startup|gd|all]"; exit 2 ;;
esac

exit $rc
```

Make it executable:

```bash
chmod +x tests/run.sh
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL. The `require config.options` etc. checks fail with
`module 'config.options' not found`, because those files do not exist yet. The
environment checks pass.

- [ ] **Step 5: Commit**

```bash
git add tests/run.sh tests/health.lua
git commit -m "test: add headless config test harness with dev isolation"
```

---

## Task 2: Options module

**Files:**
- Create: `lua/config/options.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua`, immediately before the final `print`/`cq` lines:

```lua
print('== options ==')
check('leader is space', vim.g.mapleader == ' ', tostring(vim.g.mapleader))
check('nerd font enabled', vim.g.have_nerd_font == true, tostring(vim.g.have_nerd_font))
check('number on', vim.o.number == true)
check('relativenumber on', vim.o.relativenumber == true)
check('undofile on', vim.o.undofile == true)
check('signcolumn yes', vim.o.signcolumn == 'yes', vim.o.signcolumn)
check('splitright', vim.o.splitright == true)
check('termguicolors', vim.o.termguicolors == true)

-- `updatetime` must be asserted in a CHILD process, not here.
--
-- Nvim's -l scripting mode forces updatetime=1 and updatecount=0 AFTER init.lua
-- runs, to make scripts responsive. Verified: under -l the value is always 1
-- even though init.lua did set it (nvim_get_option_info2 reports was_set=true,
-- last_set_sid=5 -- the assignment is recorded, then overridden), while the same
-- config at normal startup yields 200. So an in-process check here would be
-- permanently unsatisfiable -- a test that can never go green.
--
-- updatetime is the ONLY option this suite asserts that -l overrides; the other
-- eight above survive intact (verified individually). It matters because it
-- drives CursorHold, which gates LSP document highlighting.
local ut = vim.system({
  'nvim', '--headless', '-u', vim.fn.stdpath 'config' .. '/init.lua',
  '-c', 'lua io.write(vim.o.updatetime)', '-c', 'qa',
}, { text = true }):wait()
-- Exact comparison on the trimmed output, not a substring match: `match '200'`
-- would also accept 1200 or 2001.
local ut_value = (ut.stdout or ''):gsub('%s', '')
check('updatetime 200 (measured at real startup)', ut_value == '200',
  ('child reported %q, code %d'):format(ut_value, ut.code))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL on `require config.options` and on the option checks
(`relativenumber on`, `updatetime 200`, etc.), since nothing sets them yet.

- [ ] **Step 3: Write minimal implementation**

Create `lua/config/options.lua`:

```lua
-- Core editor options. No plugin dependencies.

local o = vim.o

-- Line numbers: absolute + relative for motion counts.
o.number = true
o.relativenumber = true

o.mouse = 'a'
o.showmode = false -- statusline already shows it

-- Scheduled because reading the OS clipboard at startup is slow.
vim.schedule(function() o.clipboard = 'unnamedplus' end)

o.breakindent = true
o.undofile = true

-- Case-insensitive search unless the pattern contains capitals or \C.
o.ignorecase = true
o.smartcase = true

o.signcolumn = 'yes' -- always reserve the column so text doesn't jump
o.updatetime = 200 -- drives CursorHold; 200ms feels responsive
o.timeoutlen = 300 -- which-key popup delay

o.splitright = true
o.splitbelow = true

o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

o.inccommand = 'split' -- live preview for :s
o.cursorline = true
o.scrolloff = 10
o.confirm = true -- prompt instead of failing on :q with unsaved changes
o.termguicolors = true

-- Treesitter-based folding, but start fully open.
o.foldmethod = 'expr'
o.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
o.foldtext = ''
o.foldlevel = 99
o.fillchars = 'fold: ,foldopen:󰅀,foldclose:󰅂,foldsep: '
```

- [ ] **Step 4: Wire it into `init.lua`**

Replace the entire contents of `init.lua` with:

```lua
-- Fast modular Neovim config. See docs/superpowers/specs/ for design rationale.
-- Requires Neovim 0.12+ (uses vim.pack).

-- Proves to tests/health.lua that this file actually executed. See the harness
-- self-check note in the plan's testing section.
vim.g.config_sentinel = true

-- Cache compiled Lua modules. Must be first.
vim.loader.enable()

-- Leader must be set before any plugin or keymap is defined.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- FiraCode Nerd Font is configured in both wezterm and iTerm2.
vim.g.have_nerd_font = true

require 'config.options'
```

- [ ] **Step 5: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS for all environment and options checks, and for
`require config.options`. Still FAIL for `config.keymaps`,
`config.autocmds`, `config.diagnostics`, `config.brazil` — those are later
tasks.

- [ ] **Step 6: Commit**

```bash
git add init.lua lua/config/options.lua tests/health.lua
git commit -m "feat: add options module and slim init.lua entrypoint"
```

---

## Task 3: Keymaps and autocmds modules

**Files:**
- Create: `lua/config/keymaps.lua`
- Create: `lua/config/autocmds.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== keymaps ==')

---Returns true if a normal-mode mapping for `lhs` exists.
---
--- Two storage quirks, both verified against nvim_get_keymap:
---   * `<leader>x` is stored with the leader ALREADY EXPANDED to its literal
---     character. With a space leader, `<leader>bd` is stored as `" bd"`
---     (bytes 32,98,100) -- NOT as `"<Space>bd"`. Comparing against
---     `"<Space>bd"` can never match.
---   * Control keys are stored uppercased: `<C-h>` is stored as `"<C-H>"`.
--- This helper normalises a `<leader>` prefix so callers can write the
--- readable form.
---@param lhs string
---@return boolean
local function has_nmap(lhs)
  local want = lhs:gsub('^<leader>', vim.g.mapleader or ' ')
  for _, m in ipairs(vim.api.nvim_get_keymap 'n') do
    if m.lhs == want then return true end
  end
  return false
end

for _, lhs in ipairs { '<C-H>', '<C-L>', '<C-J>', '<C-K>', '<leader>bd' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end

print('== autocmds ==')
check(
  'yank highlight augroup',
  #vim.api.nvim_get_autocmds { group = 'config-highlight-yank', event = 'TextYankPost' } > 0
)
```

Note on leader mappings: `nvim_get_keymap` reports them with the leader expanded
to its **literal character**, so `<leader>bd` is stored as `" bd"` — a real
space byte, not the string `<Space>`. The `has_nmap` helper above performs that
substitution, so every call site can use the readable `<leader>x` form. Control
keys are stored uppercased (`<C-h>` → `<C-H>`), which is why those are written
in uppercase.

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL on every `nmap` check and on `yank highlight augroup`, plus the
existing `require config.keymaps` / `config.autocmds` failures.

- [ ] **Step 3: Write the keymaps implementation**

Create `lua/config/keymaps.lua`:

```lua
-- Non-plugin keymaps. LSP keymaps live in lua/plugins/lsp.lua (buffer-local
-- on LspAttach); picker keymaps live in lua/plugins/picker.lua.
--
-- Scheme follows LazyVim conventions to preserve existing muscle memory.

local map = vim.keymap.set

-- Clear search highlight.
map('n', '<Esc>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })

-- Window navigation.
map('n', '<C-h>', '<C-w>h', { desc = 'Go to left window' })
map('n', '<C-j>', '<C-w>j', { desc = 'Go to lower window' })
map('n', '<C-k>', '<C-w>k', { desc = 'Go to upper window' })
map('n', '<C-l>', '<C-w>l', { desc = 'Go to right window' })

-- Window resizing.
map('n', '<C-Up>', '<cmd>resize +2<CR>', { desc = 'Increase window height' })
map('n', '<C-Down>', '<cmd>resize -2<CR>', { desc = 'Decrease window height' })
map('n', '<C-Left>', '<cmd>vertical resize -2<CR>', { desc = 'Decrease window width' })
map('n', '<C-Right>', '<cmd>vertical resize +2<CR>', { desc = 'Increase window width' })

-- Buffers.
map('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
map('n', '<S-l>', '<cmd>bnext<CR>', { desc = 'Next buffer' })
map('n', '<leader>bd', '<cmd>bdelete<CR>', { desc = 'Delete buffer' })
map('n', '<leader>bo', function()
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted and not vim.bo[buf].modified then
      vim.api.nvim_buf_delete(buf, {})
    end
  end
end, { desc = 'Delete other buffers' })

-- Move lines, keeping selection.
map('n', '<A-j>', '<cmd>m .+1<CR>==', { desc = 'Move line down' })
map('n', '<A-k>', '<cmd>m .-2<CR>==', { desc = 'Move line up' })
map('v', '<A-j>', ":m '>+1<CR>gv=gv", { desc = 'Move selection down' })
map('v', '<A-k>', ":m '<-2<CR>gv=gv", { desc = 'Move selection up' })

-- Keep the cursor centred when jumping half-pages and through search results.
map('n', '<C-d>', '<C-d>zz', { desc = 'Half page down (centred)' })
map('n', '<C-u>', '<C-u>zz', { desc = 'Half page up (centred)' })
map('n', 'n', 'nzzzv', { desc = 'Next search result (centred)' })
map('n', 'N', 'Nzzzv', { desc = 'Previous search result (centred)' })

-- Indent without losing the visual selection.
map('v', '<', '<gv', { desc = 'Indent left' })
map('v', '>', '>gv', { desc = 'Indent right' })

-- Save.
map({ 'i', 'x', 'n', 's' }, '<C-s>', '<cmd>w<CR><Esc>', { desc = 'Save file' })

-- Terminal: escape to normal mode.
map('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Quickfix / location list.
map('n', '<leader>xq', '<cmd>copen<CR>', { desc = 'Quickfix list' })
map('n', '<leader>xl', '<cmd>lopen<CR>', { desc = 'Location list' })
```

- [ ] **Step 4: Write the autocmds implementation**

Create `lua/config/autocmds.lua`:

```lua
-- Editor autocommands. Plugin-specific autocmds live with their plugin.

local function augroup(name) return vim.api.nvim_create_augroup('config-' .. name, { clear = true }) end

-- Briefly highlight yanked text.
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight on yank',
  group = augroup 'highlight-yank',
  callback = function() vim.hl.on_yank() end,
})

-- Reopen files at the last cursor position.
vim.api.nvim_create_autocmd('BufReadPost', {
  desc = 'Restore last cursor position',
  group = augroup 'last-loc',
  callback = function(ev)
    if vim.bo[ev.buf].filetype == 'gitcommit' then return end
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= line_count then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
  end,
})

-- Close throwaway windows with plain `q`.
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Close scratch filetypes with q',
  group = augroup 'close-with-q',
  pattern = { 'help', 'qf', 'man', 'lspinfo', 'checkhealth', 'notify', 'query' },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = ev.buf, silent = true, desc = 'Close window' })
  end,
})

-- Create missing parent directories on save.
vim.api.nvim_create_autocmd('BufWritePre', {
  desc = 'Auto-create parent directories',
  group = augroup 'auto-create-dir',
  callback = function(ev)
    if ev.match:match '^%w%w+://' then return end -- skip oil://, fugitive:// etc.
    vim.fn.mkdir(vim.fn.fnamemodify(vim.uv.fs_realpath(ev.match) or ev.match, ':p:h'), 'p')
  end,
})

-- Disable line numbers and wrap text in terminal buffers.
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Terminal buffer settings',
  group = augroup 'term-open',
  callback = function()
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = 'no'
  end,
})
```

- [ ] **Step 5: Wire both into `init.lua`**

In `init.lua`, replace the line `require 'config.options'` with:

```lua
require 'config.options'
require 'config.keymaps'
require 'config.autocmds'
```

- [ ] **Step 6: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS for all keymap and autocmd checks and for
`require config.keymaps` / `require config.autocmds`. Still FAIL for
`config.diagnostics` and `config.brazil`.

- [ ] **Step 7: Commit**

```bash
git add init.lua lua/config/keymaps.lua lua/config/autocmds.lua tests/health.lua
git commit -m "feat: add keymaps and autocmds modules"
```

---

## Task 4: Hybrid diagnostics module

Implements the researched pattern from spec section "Diagnostics research".

**Files:**
- Create: `lua/config/diagnostics.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== diagnostics ==')
local dcfg = vim.diagnostic.config()

check('virtual_text is a table', type(dcfg.virtual_text) == 'table', type(dcfg.virtual_text))
check(
  'virtual_text.current_line == false (all lines EXCEPT cursor line)',
  type(dcfg.virtual_text) == 'table' and dcfg.virtual_text.current_line == false,
  type(dcfg.virtual_text) == 'table' and tostring(dcfg.virtual_text.current_line) or 'n/a'
)
check('virtual_lines is a table', type(dcfg.virtual_lines) == 'table', type(dcfg.virtual_lines))
check(
  'virtual_lines.current_line == true',
  type(dcfg.virtual_lines) == 'table' and dcfg.virtual_lines.current_line == true
)
check('severity_sort on', dcfg.severity_sort == true)
check('update_in_insert off', dcfg.update_in_insert == false)
check('signs configured', dcfg.signs ~= false and dcfg.signs ~= nil)
check('gK toggle mapped', has_nmap 'gK')
```

`has_nmap` is defined in Task 3 Step 1 and is in scope here.

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL. Neovim 0.12 defaults both handlers off — verified locally as
`{ underline = true, virtual_lines = false, virtual_text = false }` — so
`virtual_text is a table` and `virtual_lines is a table` both fail, as does
`gK toggle mapped`.

- [ ] **Step 3: Write minimal implementation**

Create `lua/config/diagnostics.lua`:

```lua
-- Hybrid diagnostic display.
--
-- `virtual_text.current_line = false` is not "disabled" -- it is a three-state
-- flag (see :help vim.diagnostic.Opts.VirtualText):
--   true  -> only the cursor line
--   false -> every line EXCEPT the cursor line
--   nil   -> every line
--
-- Pairing `virtual_text { current_line = false }` with
-- `virtual_lines { current_line = true }` gives compact markers everywhere and
-- full multi-line detail on the line under the cursor. This matters for long
-- Rust and TypeScript type errors that virtual text truncates.
--
-- Neither handler issues an LSP request: diagnostics are pushed by the server
-- via textDocument/publishDiagnostics and rendered as extmarks. This is
-- categorically unlike codelens, which pulls per symbol. See the "no codelens"
-- rule in the design spec.

--- Show the jumped-to diagnostic as virtual lines. Mirrors
--- *diagnostic-on-jump-example* in :help diagnostic.
---@param diagnostic? vim.Diagnostic
---@param bufnr integer
local function on_jump(diagnostic, bufnr)
  if not diagnostic then return end
  vim.diagnostic.show(diagnostic.namespace, bufnr, { diagnostic }, {
    virtual_lines = { current_line = true },
    virtual_text = false,
  })
end

vim.diagnostic.config {
  underline = { severity = { min = vim.diagnostic.severity.WARN } },
  update_in_insert = false,
  severity_sort = true,

  virtual_text = {
    current_line = false, -- everywhere except the cursor line
    source = 'if_many',
    prefix = '●',
    spacing = 2,
  },

  virtual_lines = {
    current_line = true, -- full detail on the cursor line only
  },

  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '󰅙 ',
      [vim.diagnostic.severity.WARN] = '󰀦 ',
      [vim.diagnostic.severity.INFO] = '󰋼 ',
      [vim.diagnostic.severity.HINT] = '󰌵 ',
    },
  },

  float = { border = 'rounded', source = 'if_many' },
  jump = { on_jump = on_jump },
}

-- Toggle virtual_lines. Mirrors *diagnostic-toggle-virtual-lines-example*.
vim.keymap.set('n', 'gK', function()
  local enabled = vim.diagnostic.config().virtual_lines
  if enabled then
    vim.diagnostic.config { virtual_lines = false }
    vim.notify('Diagnostic virtual_lines: off', vim.log.levels.INFO)
  else
    vim.diagnostic.config { virtual_lines = { current_line = true } }
    vim.notify('Diagnostic virtual_lines: on', vim.log.levels.INFO)
  end
end, { desc = 'Toggle diagnostic virtual_lines' })

-- Diagnostic navigation. vim.diagnostic.jump respects the on_jump handler above.
vim.keymap.set('n', ']d', function() vim.diagnostic.jump { count = 1, float = false } end, { desc = 'Next diagnostic' })
vim.keymap.set('n', '[d', function() vim.diagnostic.jump { count = -1, float = false } end, { desc = 'Previous diagnostic' })
vim.keymap.set('n', ']e', function() vim.diagnostic.jump { count = 1, severity = vim.diagnostic.severity.ERROR, float = false } end, { desc = 'Next error' })
vim.keymap.set('n', '[e', function() vim.diagnostic.jump { count = -1, severity = vim.diagnostic.severity.ERROR, float = false } end, { desc = 'Previous error' })
vim.keymap.set('n', '<leader>cd', vim.diagnostic.open_float, { desc = 'Line diagnostics' })
```

- [ ] **Step 4: Wire it into `init.lua`**

In `init.lua`, after `require 'config.autocmds'`, add:

```lua
require 'config.diagnostics'
```

- [ ] **Step 5: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS for all diagnostics checks. Only `require config.brazil` should
still fail.

- [ ] **Step 6: Commit**

```bash
git add init.lua lua/config/diagnostics.lua tests/health.lua
git commit -m "feat: add hybrid virtual_text/virtual_lines diagnostics"
```

---

## Task 5: Brazil exclude module

This is **fix #2** for the `gd` latency: Brazil `build/` symlinks point
cross-volume at 2,558 Python files that pyright otherwise indexes.

**Files:**
- Create: `lua/config/brazil.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== brazil excludes ==')
local ok_brazil, brazil = pcall(require, 'config.brazil')
check('config.brazil loads', ok_brazil, tostring(brazil))
if ok_brazil then
  local function contains(list, want)
    for _, v in ipairs(list) do
      if v == want then return true end
    end
    return false
  end
  -- The build/ symlink is the specific cause of the measured gd latency.
  check('excludes **/build', contains(brazil.exclude_globs, '**/build'))
  check('excludes **/.bemol', contains(brazil.exclude_globs, '**/.bemol'))
  check('excludes **/node_modules', contains(brazil.exclude_globs, '**/node_modules'))
  check('excludes **/target', contains(brazil.exclude_globs, '**/target'))
  check('python root markers include Config', contains(brazil.python_root_markers, 'Config'))
  check('python root markers include pyproject.toml', contains(brazil.python_root_markers, 'pyproject.toml'))
  check('exclude_globs is non-empty', #brazil.exclude_globs >= 8, tostring(#brazil.exclude_globs))
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'config.brazil' not found`.

- [ ] **Step 3: Write minimal implementation**

Create `lua/config/brazil.lua`:

```lua
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
```

- [ ] **Step 4: Wire it into `init.lua`**

In `init.lua`, after `require 'config.diagnostics'`, add:

```lua
-- Required for its side-effect-free data by lua/plugins/lsp.lua; required here
-- so a load error surfaces at startup rather than on first LSP attach.
require 'config.brazil'
```

- [ ] **Step 5: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS — all checks including every `config.*` module require. Exit
code 0.

- [ ] **Step 6: Commit**

```bash
git add init.lua lua/config/brazil.lua tests/health.lua
git commit -m "feat: add Brazil build/ exclude globs and root markers"
```

---

## Task 6: Plugin bootstrap and UI plugins

**Files:**
- Modify: `init.lua`
- Create: `lua/plugins/ui.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== ui plugins ==')

---@param name string module name to require
local function loads(name)
  local ok, err = pcall(require, name)
  check('require ' .. name, ok, tostring(err))
end

loads 'which-key'
loads 'tokyonight'
loads 'mini.ai'
loads 'mini.surround'
loads 'mini.icons'
loads 'todo-comments'

check('colorscheme is tokyonight', (vim.g.colors_name or ''):match 'tokyonight' ~= nil, tostring(vim.g.colors_name))
check('lualine loaded', pcall(require, 'lualine'))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'which-key' not found` and similar for each.

- [ ] **Step 3: Add the `vim.pack` build-hook bootstrap to `init.lua`**

In `init.lua`, insert this **after** `vim.g.have_nerd_font = true` and
**before** the `require 'config.options'` line:

```lua
-- Some plugins need a build step after install or update. vim.pack emits
-- PackChanged for this; see :help vim.pack-events.
local function run_build(name, cmd, cwd)
  local result = vim.system(cmd, { cwd = cwd }):wait()
  if result.code ~= 0 then
    local output = (result.stderr ~= '' and result.stderr) or result.stdout or 'no output'
    vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_autocmd('PackChanged', {
  desc = 'Run plugin build steps',
  callback = function(ev)
    local kind, name, path = ev.data.kind, ev.data.spec.name, ev.data.path
    if kind ~= 'install' and kind ~= 'update' then return end

    if name == 'LuaSnip' and vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then
      run_build(name, { 'make', 'install_jsregexp' }, path)
    elseif name == 'nvim-treesitter' then
      if not ev.data.active then vim.cmd.packadd 'nvim-treesitter' end
      vim.cmd 'TSUpdate'
    end
  end,
})

--- Shorthand for GitHub plugin sources.
---@param repo string "owner/name"
---@return string
_G.gh = function(repo) return 'https://github.com/' .. repo end
```

Then, after the existing `require 'config.brazil'` line, add:

```lua
require 'plugins.ui'
```

- [ ] **Step 4: Write the UI plugins implementation**

Create `lua/plugins/ui.lua`:

```lua
-- Colorscheme, statusline, keymap hints and small editing utilities.

vim.pack.add {
  gh 'folke/tokyonight.nvim',
  gh 'folke/which-key.nvim',
  gh 'folke/todo-comments.nvim',
  gh 'nvim-mini/mini.nvim',
  gh 'nvim-lualine/lualine.nvim',
}

-- Colorscheme first, so later plugins pick up its highlight groups.
require('tokyonight').setup {
  style = 'night',
  styles = { comments = { italic = false } },
}
vim.cmd.colorscheme 'tokyonight-night'

-- Icons. A Nerd Font is configured in both wezterm and iTerm2.
require('mini.icons').setup()
MiniIcons.mock_nvim_web_devicons() -- for plugins that still require nvim-web-devicons

-- Extra text objects: va) vi" ci' etc. `aa`/`ii` avoid clashing with the
-- built-in treesitter incremental-selection maps on Neovim 0.12.
require('mini.ai').setup { mappings = { around_next = 'aa', inside_next = 'ii' }, n_lines = 500 }

-- Add/delete/replace surroundings: saiw) sd' sr)'
require('mini.surround').setup()

require('lualine').setup {
  options = {
    theme = 'tokyonight',
    globalstatus = true,
    section_separators = '',
    component_separators = '|',
  },
  sections = {
    lualine_c = { { 'filename', path = 1 } },
    lualine_x = { 'diagnostics', 'filetype' },
  },
}

require('todo-comments').setup { signs = false }

require('which-key').setup {
  delay = 200,
  icons = { mappings = vim.g.have_nerd_font },
  spec = {
    { '<leader>b', group = 'Buffer' },
    { '<leader>c', group = 'Code' },
    { '<leader>d', group = 'Debug' },
    { '<leader>f', group = 'Find/File' },
    { '<leader>g', group = 'Git' },
    { '<leader>s', group = 'Search' },
    { '<leader>t', group = 'Test' },
    { '<leader>u', group = 'UI/Toggle' },
    { '<leader>x', group = 'Diagnostics/Lists' },
  },
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: On the first run `vim.pack` downloads the plugins, which takes time
and prints progress. Then PASS for all UI checks.

If plugin download interferes with the headless run, pre-install once with:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -c 'qa'
```

then re-run `tests/run.sh health`.

- [ ] **Step 6: Commit**

```bash
git add init.lua lua/plugins/ui.lua tests/health.lua
git commit -m "feat: add vim.pack build hooks and UI plugins"
```

---

## Task 7: Startup time regression gate

**Files:**
- Create: `tests/startup.lua`

- [ ] **Step 1: Write the failing test**

Create `tests/startup.lua`:

```lua
-- Startup time regression gate.
--
-- Guards the spec's startup acceptance criterion.
--
-- Run: NVIM_APPNAME=nvim-dev nvim --headless -l tests/startup.lua

-- 60ms is the spec's acceptance criterion, not an arbitrary number.
-- Reference points measured on this machine:
--   bare nvim, no config, no plugins : ~17-18 ms  (the floor)
--   previous LazyVim install         : 167-277 ms (the baseline to beat)
-- So the budget allows roughly 42ms for everything this config loads.
--
-- vim.pack.add is eager, so every plugin added counts against this. If a later
-- task pushes past 60ms, that is a real signal: either defer a plugin behind
-- packadd in an autocmd, or consciously raise this with a recorded reason.
-- Do not raise it silently -- the spec's criterion is what the user approved.
local BUDGET_MS = 60
local RUNS = 3

local times = {}
for i = 1, RUNS do
  local log = ('/tmp/nvim-startup-%d.log'):format(i)
  os.remove(log)
  -- Spawn a child nvim with the same NVIM_APPNAME so it loads this config.
  --
  -- No -u here, deliberately: this measures a NORMAL startup, where Neovim
  -- discovers init.lua through NVIM_APPNAME. That is the number the user
  -- actually experiences. (-u is only needed for `-l` script runs, which skip
  -- user config.)
  --
  -- `clear = false` keeps the inherited environment; a bare `env` table would
  -- drop XDG_* and TERM and change what gets loaded.
  local result = vim.system({ 'nvim', '--headless', '--startuptime', log, '-c', 'qa' }, {
    clear_env = false,
    env = { NVIM_APPNAME = 'nvim-dev' },
  }):wait()
  if result.code ~= 0 then
    print(('  FAIL child nvim exited %d'):format(result.code))
    vim.cmd 'cq 1'
  end

  -- The `--- NVIM STARTED ---` line carries the cumulative total, e.g.
  --   030.284  000.084: --- NVIM STARTED ---
  -- Anchor on that marker rather than "last numeric line", so a trailing log
  -- entry cannot silently change what is being measured.
  local total
  for line in io.lines(log) do
    local t = line:match '^(%d+%.%d+).*NVIM STARTED'
    if t then total = tonumber(t) end
  end
  if not total then
    print '  FAIL could not find "--- NVIM STARTED ---" in startuptime log'
    vim.cmd 'cq 1'
  end
  times[#times + 1] = total
  print(('  run %d: %.1f ms'):format(i, total))
end

table.sort(times)
local median = times[math.ceil(#times / 2)]
print(('\nmedian: %.1f ms (budget %d ms)'):format(median, BUDGET_MS))

if median <= BUDGET_MS then
  print '  ok   startup within budget'
  vim.cmd 'cq 0'
else
  print(('  FAIL startup %.1f ms exceeds budget %d ms'):format(median, BUDGET_MS))
  vim.cmd 'cq 1'
end
```

- [ ] **Step 2: Run the test and record the number**

Run: `tests/run.sh startup`

Expected: PASS at this stage — only UI plugins are installed so far, so startup
should be comfortably under 60ms. Record the median; it will grow as later tasks add
plugins.

If it already exceeds 60ms, stop and investigate before continuing: something
is loading eagerly that should not be.

- [ ] **Step 3: Commit**

```bash
git add tests/startup.lua
git commit -m "test: add startup time regression gate"
```

---

## Task 8: Treesitter with Smithy filetype

**Files:**
- Create: `lua/plugins/treesitter.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== treesitter ==')
loads 'nvim-treesitter'
check('smithy filetype registered', vim.filetype.match { filename = 'model.smithy' } == 'smithy', tostring(vim.filetype.match { filename = 'model.smithy' }))
```

`loads` is defined in Task 6 Step 1 and is in scope.

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'nvim-treesitter' not found` and
`smithy filetype registered` returning `nil`.

- [ ] **Step 3: Write minimal implementation**

Create `lua/plugins/treesitter.lua`:

```lua
-- Treesitter: highlighting, indentation and folds.
--
-- Uses the `main` branch, which is the current API (`.install()` /
-- `.get_installed()`) rather than the legacy `master` branch's
-- `configs.setup { ensure_installed = ... }`.

vim.pack.add {
  { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' },
}

-- Smithy is an Amazon IDL. There are 54 .smithy files in this user's
-- workspaces, so register the filetype for highlighting. No language server:
-- smithy-language-server is JVM-based and requires Amazon-internal setup.
vim.filetype.add { extension = { smithy = 'smithy' } }

local parsers = {
  'bash',
  'c',
  'css',
  'diff',
  'dockerfile',
  'gitcommit',
  'gitignore',
  'go',
  'gomod',
  'html',
  'javascript',
  'jsdoc',
  'json',
  'json5',
  'jsonc',
  'lua',
  'luadoc',
  'luap',
  'markdown',
  'markdown_inline',
  'python',
  'query',
  'regex',
  'rust',
  'smithy',
  'toml',
  'tsx',
  'typescript',
  'vim',
  'vimdoc',
  'yaml',
}

require('nvim-treesitter').install(parsers)

--- Start treesitter for `language` in `buf`, enabling indent when a query exists.
---@param buf integer
---@param language string
local function try_attach(buf, language)
  if not vim.treesitter.language.add(language) then return end
  vim.treesitter.start(buf, language)
  if vim.treesitter.query.get(language, 'indents') ~= nil then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
end

local available = require('nvim-treesitter').get_available()

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Start treesitter, installing the parser on demand',
  group = vim.api.nvim_create_augroup('config-treesitter', { clear = true }),
  callback = function(args)
    local language = vim.treesitter.language.get_lang(args.match)
    if not language then return end

    local installed = require('nvim-treesitter').get_installed 'parsers'
    if vim.tbl_contains(installed, language) then
      try_attach(args.buf, language)
    elseif vim.tbl_contains(available, language) then
      require('nvim-treesitter').install(language):await(function() try_attach(args.buf, language) end)
    else
      -- Parser may exist outside nvim-treesitter's registry.
      try_attach(args.buf, language)
    end
  end,
})
```

- [ ] **Step 4: Wire it into `init.lua`**

In `init.lua`, after `require 'plugins.ui'`, add:

```lua
require 'plugins.treesitter'
```

- [ ] **Step 5: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS. Note that the first run compiles parsers, which takes a while.
Pre-warm with:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -c 'sleep 60' -c 'qa'
```

- [ ] **Step 6: Verify Smithy highlighting on a real file**

```bash
NVIM_APPNAME=nvim-dev nvim ~/workplace/PanoramaMCP/src/PanoramaMCPModel/*.smithy
```

Then in Neovim run `:echo &filetype` (expect `smithy`) and
`:lua print(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil)`
(expect `true`). Quit with `:qa`.

If no `.smithy` file exists at that path, find one with:
`find ~/workplace -name '*.smithy' | head -1`

- [ ] **Step 7: Commit**

```bash
git add init.lua lua/plugins/treesitter.lua tests/health.lua
git commit -m "feat: add treesitter with Smithy filetype support"
```

---

## Task 9: LSP — servers, enablement and keymaps

The largest task. Implements **fix #2** (Brazil excludes reach the servers) and
the single-owner enablement rule.

**Files:**
- Create: `lua/plugins/lsp.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== lsp ==')
loads 'mason'
loads 'mason-lspconfig'
loads 'lspconfig'

--- Reads back a server's resolved configuration.
---
--- Must use the INDEX form `vim.lsp.config[name]`, not the call form
--- `vim.lsp.config(name)`. The call form is the setter and raises
--- "cfg: expected table (hint: to resolve a config, use
--- vim.lsp.config[\"name\"]), got nil" when called with one argument.
--- Verified on 0.12. Unconfigured servers return nil via the index form.
---@param name string
---@return table|nil
local function server_cfg(name)
  local ok, cfg = pcall(function() return vim.lsp.config[name] end)
  return (ok and type(cfg) == 'table') and cfg or nil
end

local bp = server_cfg 'basedpyright'
check('basedpyright configured', bp ~= nil)
if bp then
  local analysis = vim.tbl_get(bp, 'settings', 'basedpyright', 'analysis') or {}
  check('basedpyright diagnosticMode openFilesOnly', analysis.diagnosticMode == 'openFilesOnly', tostring(analysis.diagnosticMode))
  local has_build = false
  for _, g in ipairs(analysis.exclude or {}) do
    if g == '**/build' then has_build = true end
  end
  check('basedpyright excludes **/build (the gd latency fix)', has_build)
  check('basedpyright root markers include Config', vim.tbl_contains(bp.root_markers or {}, 'Config'))
end

check('vtsls configured', server_cfg 'vtsls' ~= nil)
check('lua_ls configured', server_cfg 'lua_ls' ~= nil)
check('ruff configured', server_cfg 'ruff' ~= nil)

-- rustaceanvim owns rust_analyzer exclusively. This config must not enable it.
-- mason-lspconfig's automatic_enable also calls vim.lsp.config + vim.lsp.enable
-- (verified in its features/automatic_enable.lua), so it must be off.
local ms_ok, ms_settings = pcall(require, 'mason-lspconfig.settings')
check('mason-lspconfig settings readable', ms_ok, tostring(ms_settings))
if ms_ok then
  check(
    'automatic_enable is false (this config owns enablement)',
    ms_settings.current.automatic_enable == false,
    vim.inspect(ms_settings.current.automatic_enable)
  )
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'mason' not found` and every server check failing.

- [ ] **Step 3: Write minimal implementation**

Create `lua/plugins/lsp.lua`:

```lua
-- Language servers.
--
-- ENABLEMENT OWNERSHIP -- read before changing anything here.
--
-- mason-lspconfig's `automatic_enable` feature calls BOTH
-- `vim.lsp.config(name, cfg)` and `vim.lsp.enable(name)`, where `cfg` comes
-- from its bundled `mason-lspconfig.lsp.<server>` module when one exists
-- (see its features/automatic_enable.lua). If it ran alongside the explicit
-- loop at the bottom of this file, every server would be configured twice and
-- mason-lspconfig's bundled settings could displace the tuning below --
-- including the basedpyright excludes that fix the `gd` latency.
--
-- Therefore: automatic_enable = false, and this file is the single owner of
-- enablement. rust_analyzer is deliberately absent from `servers` because
-- rustaceanvim owns it (see lua/plugins/rust.lua); its README warns that also
-- running the lspconfig setup "may cause conflicts".

local brazil = require 'config.brazil'

vim.pack.add {
  gh 'neovim/nvim-lspconfig',
  gh 'mason-org/mason.nvim',
  gh 'mason-org/mason-lspconfig.nvim',
  gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  gh 'j-hui/fidget.nvim',
}

require('fidget').setup {} -- LSP progress in the corner

---@type table<string, vim.lsp.Config>
local servers = {
  -- Python: basedpyright owns navigation and hover; ruff owns lint and
  -- organize-imports. The `exclude` list is the single most important setting
  -- in this file -- see lua/config/brazil.lua for why.
  basedpyright = {
    root_markers = brazil.python_root_markers,
    settings = {
      basedpyright = {
        analysis = {
          -- Workspace-wide diagnostics would re-scan everything on each edit.
          diagnosticMode = 'openFilesOnly',
          exclude = brazil.exclude_globs,
          useLibraryCodeForTypes = true,
          autoImportCompletions = true,
          typeCheckingMode = 'standard',
        },
      },
    },
  },

  ruff = {
    root_markers = brazil.python_root_markers,
    -- basedpyright is the single source for hover, so silence ruff's.
    on_attach = function(client)
      client.server_capabilities.hoverProvider = false
    end,
  },

  -- TypeScript. Perf settings come from vtsls' own README: tsserver returns
  -- very large completion sets, and its default 3GB heap is low for big repos.
  vtsls = {
    root_markers = brazil.node_root_markers,
    settings = {
      vtsls = {
        experimental = {
          completion = {
            enableServerSideFuzzyMatch = true,
            entriesLimit = 250,
          },
        },
      },
      typescript = {
        tsserver = { maxTsServerMemory = 8192 },
        preferences = { includePackageJsonAutoImports = 'off' },
        inlayHints = {
          parameterNames = { enabled = 'literals' },
          variableTypes = { enabled = false },
        },
      },
    },
  },

  lua_ls = {
    on_init = function(client)
      -- stylua owns formatting.
      client.server_capabilities.documentFormattingProvider = false

      -- Skip the expensive runtime-library scan when the project has its own
      -- .luarc.json.
      if client.workspace_folders then
        local path = client.workspace_folders[1].name
        if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then
          return
        end
      end

      client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua or {}, {
        runtime = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
        workspace = {
          checkThirdParty = false,
          library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
            '${3rd}/luv/library',
          }),
        },
      })
    end,
    settings = {
      Lua = {
        format = { enable = false },
        diagnostics = { globals = { 'vim', 'gh', 'MiniIcons' } },
        completion = { callSnippet = 'Replace' },
      },
    },
  },

  gopls = {
    settings = {
      gopls = {
        analyses = { unusedparams = true },
        staticcheck = true,
      },
    },
  },

  bashls = {},
  jsonls = {},
  yamlls = {},
  taplo = {},
  marksman = {},
}

-- `pyright` is installed via mason-tool-installer as a fallback (the spec keeps
-- it in case basedpyright misbehaves on Brazil layouts) but is deliberately NOT
-- in `servers`: enabling both would run two type checkers over the same buffer,
-- doubling the analysis work this config exists to reduce. To switch, comment
-- out the basedpyright entry above and add:
--
--   pyright = {
--     root_markers = brazil.python_root_markers,
--     settings = { python = { analysis = {
--       diagnosticMode = 'openFilesOnly',
--       exclude = brazil.exclude_globs,
--     } } },
--   }
--
-- Note the settings key is `python`, not `basedpyright`.

require('mason').setup {}

-- See the ownership note at the top of this file.
require('mason-lspconfig').setup { automatic_enable = false }

require('mason-tool-installer').setup {
  ensure_installed = {
    -- Servers (Mason package names are mapped from lspconfig names).
    'basedpyright',
    'pyright', -- fallback only; NOT enabled (see note under the servers table)
    'ruff',
    'vtsls',
    'lua-language-server',
    'gopls',
    'bash-language-server',
    'json-lsp',
    'yaml-language-server',
    'taplo',
    'marksman',
    -- Formatters and linters (used by lua/plugins/format.lua).
    'stylua',
    'prettier',
    'shfmt',
    'shellcheck',
    'gofumpt',
    'goimports',
    'markdownlint-cli2',
    -- Debug adapters (used by lua/plugins/dap.lua).
    'debugpy',
    'codelldb',
  },
  run_on_start = false, -- installing during startup would slow it down
}

-- Buffer-local LSP keymaps. LazyVim-style, to preserve muscle memory.
--
-- NOTE: no codelens anywhere. Reference-counting codelens was the primary
-- cause of the multi-second `gd` latency this config exists to fix: it issued
-- textDocument/references per visible function on CursorMoved, and definition
-- requests queued behind those whole-workspace scans.
vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP buffer keymaps',
  group = vim.api.nvim_create_augroup('config-lsp-attach', { clear = true }),
  callback = function(event)
    local buf = event.buf
    local function map(keys, fn, desc, mode)
      vim.keymap.set(mode or 'n', keys, fn, { buffer = buf, desc = 'LSP: ' .. desc })
    end

    local fzf = require 'fzf-lua'

    map('gd', fzf.lsp_definitions, 'Goto definition')
    map('gr', fzf.lsp_references, 'References')
    map('gI', fzf.lsp_implementations, 'Goto implementation')
    map('gy', fzf.lsp_typedefs, 'Goto type definition')
    map('gD', vim.lsp.buf.declaration, 'Goto declaration')
    map('K', vim.lsp.buf.hover, 'Hover')
    -- Signature help is deliberately NOT on `gK`: lua/config/diagnostics.lua
    -- owns `gK` as the virtual_lines toggle (per the spec's keymap table), and
    -- a buffer-local LspAttach map would silently shadow it in exactly the
    -- buffers where the toggle is most useful.
    map('<leader>ck', vim.lsp.buf.signature_help, 'Signature help')
    map('<C-k>', vim.lsp.buf.signature_help, 'Signature help', 'i')
    map('<leader>cr', vim.lsp.buf.rename, 'Rename')
    map('<leader>ca', vim.lsp.buf.code_action, 'Code action', { 'n', 'x' })
    map('<leader>cs', fzf.lsp_document_symbols, 'Document symbols')
    map('<leader>cS', fzf.lsp_live_workspace_symbols, 'Workspace symbols')

    local client = vim.lsp.get_client_by_id(event.data.client_id)

    -- Highlight other references to the symbol under the cursor. This uses
    -- textDocument/documentHighlight, which is buffer-local and cheap --
    -- unlike textDocument/references, which is workspace-wide.
    if client and client:supports_method('textDocument/documentHighlight', buf) then
      local hl_group = vim.api.nvim_create_augroup('config-lsp-highlight', { clear = false })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        buffer = buf,
        group = hl_group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer = buf,
        group = hl_group,
        callback = vim.lsp.buf.clear_references,
      })
      vim.api.nvim_create_autocmd('LspDetach', {
        group = vim.api.nvim_create_augroup('config-lsp-detach', { clear = true }),
        callback = function(ev2)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds { group = 'config-lsp-highlight', buffer = ev2.buf }
        end,
      })
    end

    if client and client:supports_method('textDocument/inlayHint', buf) then
      map('<leader>uh', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = buf }, { bufnr = buf })
      end, 'Toggle inlay hints')
    end
  end,
})

-- Single owner of enablement. rust_analyzer is intentionally not in `servers`.
for name, cfg in pairs(servers) do
  vim.lsp.config(name, cfg)
  vim.lsp.enable(name)
end
```

- [ ] **Step 4: Wire it into `init.lua`**

In `init.lua`, after `require 'plugins.treesitter'`, add:

```lua
require 'plugins.picker' -- must precede lsp: LspAttach keymaps require fzf-lua
require 'plugins.lsp'
```

`lua/plugins/picker.lua` is created in Task 10. Until then the health test will
fail on `module 'plugins.picker' not found` — that is expected and is fixed by
the next task.

- [ ] **Step 5: Run test to verify it fails for the expected reason only**

Run: `tests/run.sh health`

Expected: FAIL, and the failure must be `module 'plugins.picker' not found`
(or `module 'fzf-lua' not found`). If any *other* failure appears, fix it
before moving on.

- [ ] **Step 6: Commit**

```bash
git add init.lua lua/plugins/lsp.lua tests/health.lua
git commit -m "feat: add LSP config with Brazil excludes and single-owner enablement"
```

---

## Task 10: Picker (fzf-lua) and explorer (oil.nvim)

**Files:**
- Create: `lua/plugins/picker.lua`
- Create: `lua/plugins/explorer.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== picker and explorer ==')
loads 'fzf-lua'
loads 'oil'

check('fzf binary on PATH', vim.fn.executable 'fzf' == 1)
check('rg binary on PATH', vim.fn.executable 'rg' == 1)
check('fd binary on PATH', vim.fn.executable 'fd' == 1)

-- jump1 makes gd land directly on a single result instead of opening a picker.
local fzf_ok, fzf_cfg = pcall(function() return require('fzf-lua.config').globals end)
check('fzf-lua globals readable', fzf_ok, tostring(fzf_cfg))
if fzf_ok and fzf_cfg and fzf_cfg.lsp then
  check('fzf-lua lsp.jump1 enabled', fzf_cfg.lsp.jump1 == true, tostring(fzf_cfg.lsp.jump1))
end

for _, lhs in ipairs { '<leader>ff', '<leader>fg', '<leader>e' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'fzf-lua' not found` and `module 'oil' not found`.

- [ ] **Step 3: Write the picker implementation**

Create `lua/plugins/picker.lua`:

```lua
-- fzf-lua: fuzzy finder backed by the native fzf binary.
--
-- Chosen over telescope and snacks.picker because filtering happens in
-- compiled code and `rg` restarts per keystroke, which scales better on large
-- repositories.
--
-- fzf-lua has no hard lazy.nvim dependency: the single reference in its
-- actions.lua is guarded by `if ... package.loaded.lazy then`, so it works
-- under vim.pack.

vim.pack.add { gh 'ibhagwan/fzf-lua' }

local fzf = require 'fzf-lua'

fzf.setup {
  -- Profiles: 'default-title' puts picker info in the window title;
  -- 'fzf-native' uses fzf's own previewer.
  { 'default-title', 'fzf-native' },
  winopts = {
    height = 0.85,
    width = 0.85,
    preview = { layout = 'flex', scrollbar = false },
  },
  files = {
    -- fd respects .gitignore and is faster than find.
    fd_opts = [[--color=never --type f --hidden --follow --exclude .git --exclude node_modules --exclude build --exclude target]],
  },
  grep = {
    rg_opts = [[--column --line-number --no-heading --color=always --smart-case --max-columns=4096 -g '!.git' -g '!node_modules' -g '!build' -g '!target']],
  },
  lsp = {
    -- Skip the picker UI entirely when there is exactly one result. This is
    -- what makes `gd` feel instant. It is fzf-lua's default; set explicitly
    -- so it survives future upstream changes.
    jump1 = true,
    async_or_timeout = 5000,
    includeDeclaration = false,
  },
}

-- Route vim.ui.select through fzf-lua (code actions, rename prompts, etc.).
fzf.register_ui_select()

local map = vim.keymap.set

-- Find. LazyVim-style <leader>f prefix.
map('n', '<leader>ff', fzf.files, { desc = 'Find files' })
map('n', '<leader>fg', fzf.live_grep, { desc = 'Grep (live)' })
map('n', '<leader>fb', fzf.buffers, { desc = 'Buffers' })
map('n', '<leader>fr', fzf.oldfiles, { desc = 'Recent files' })
map('n', '<leader>fc', function() fzf.files { cwd = vim.fn.stdpath 'config' } end, { desc = 'Find config file' })
map('n', '<leader><leader>', fzf.buffers, { desc = 'Buffers' })

-- Search. <leader>s prefix.
map('n', '<leader>sh', fzf.helptags, { desc = 'Search help' })
map('n', '<leader>sk', fzf.keymaps, { desc = 'Search keymaps' })
map('n', '<leader>sc', fzf.commands, { desc = 'Search commands' })
map('n', '<leader>sr', fzf.resume, { desc = 'Resume last search' })
map('n', '<leader>sd', fzf.diagnostics_document, { desc = 'Document diagnostics' })
map('n', '<leader>sD', fzf.diagnostics_workspace, { desc = 'Workspace diagnostics' })
map({ 'n', 'v' }, '<leader>sw', fzf.grep_cword, { desc = 'Search word under cursor' })
map('n', '<leader>/', fzf.lgrep_curbuf, { desc = 'Grep current buffer' })

-- Git pickers.
map('n', '<leader>gc', fzf.git_commits, { desc = 'Git commits' })
map('n', '<leader>gs', fzf.git_status, { desc = 'Git status' })
map('n', '<leader>gb', fzf.git_branches, { desc = 'Git branches' })
```

- [ ] **Step 4: Write the explorer implementation**

Create `lua/plugins/explorer.lua`:

```lua
-- oil.nvim: edit the filesystem as a normal buffer.
--
-- fzf-lua has no tree view, so this fills that gap. oil is a
-- single-directory, vinegar-style explorer rather than a persistent sidebar
-- tree: you edit the buffer (rename lines, delete lines, add lines) and `:w`
-- applies the filesystem changes. Its README warns against lazy-loading it,
-- so it is loaded eagerly.

vim.pack.add { gh 'stevearc/oil.nvim' }

require('oil').setup {
  default_file_explorer = true,
  columns = { 'icon' },
  view_options = {
    show_hidden = true,
    -- Hide Brazil build symlinks and VCS noise from the listing.
    is_hidden_file = function(name) return name == '..' or name == '.git' end,
  },
  keymaps = {
    ['<C-h>'] = false, -- keep window navigation
    ['<C-l>'] = false,
    ['q'] = 'actions.close',
  },
  float = { padding = 4, max_width = 120, max_height = 40 },
}

vim.keymap.set('n', '<leader>e', '<cmd>Oil --float<CR>', { desc = 'File explorer (float)' })
vim.keymap.set('n', '-', '<cmd>Oil<CR>', { desc = 'Open parent directory' })
```

- [ ] **Step 5: Wire the explorer into `init.lua`**

In `init.lua`, after `require 'plugins.lsp'`, add:

```lua
require 'plugins.explorer'
```

`require 'plugins.picker'` was already added in Task 9 Step 4.

- [ ] **Step 6: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS for all checks, including the previously failing LSP checks now
that fzf-lua exists. Exit code 0.

- [ ] **Step 7: Commit**

```bash
git add init.lua lua/plugins/picker.lua lua/plugins/explorer.lua tests/health.lua
git commit -m "feat: add fzf-lua picker with jump1 and oil.nvim explorer"
```

---

## Task 11: The `gd` latency gate

This is the acceptance test for the user's original complaint. It must be
written before the config is declared working.

**Files:**
- Create: `tests/gd_latency.lua`

- [ ] **Step 1: Write the failing test**

Create `tests/gd_latency.lua`:

```lua
-- Measures textDocument/definition round-trip latency on a real Brazil Python
-- package -- the exact operation the user reported as taking "ages".
--
-- The previous config had two compounding causes:
--   1. lensline.nvim issued textDocument/references per visible function on
--      CursorMoved, so definition requests queued behind whole-workspace scans.
--   2. Brazil's build/ symlink pointed cross-volume at 2,558 Python files that
--      pyright indexed. The target package below has only 129 real .py files,
--      so roughly 20x more work than necessary.
--
-- Run: NVIM_APPNAME=nvim-dev nvim --headless -l tests/gd_latency.lua

local BUDGET_MS = 500
local ATTACH_TIMEOUT_MS = 60000

local target = vim.fn.expand '~/workplace/Qualo/src/Qualo/src/backend_lambda/main.py'

if vim.fn.filereadable(target) ~= 1 then
  print(('SKIP: %s not readable (Brazil workspace not mounted?)'):format(target))
  vim.cmd 'cq 0'
end

print(('target: %s'):format(target))
vim.cmd.edit(target)
local buf = vim.api.nvim_get_current_buf()

-- Wait for basedpyright to attach and finish initial indexing.
local attached = vim.wait(ATTACH_TIMEOUT_MS, function()
  local clients = vim.lsp.get_clients { bufnr = buf, name = 'basedpyright' }
  return #clients > 0 and clients[1].initialized
end, 200)

if not attached then
  print '  FAIL basedpyright did not attach within 60s'
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients { bufnr = buf }) do
    names[#names + 1] = c.name
  end
  print('  attached clients: ' .. (next(names) and table.concat(names, ', ') or '(none)'))
  vim.cmd 'cq 1'
end

print '  basedpyright attached'

-- Confirm the exclusion actually reached the live client. Reading it off the
-- attached client (rather than off vim.lsp.config) proves it survived
-- resolution and was handed to the server, which is the property that matters.
local client = vim.lsp.get_clients { bufnr = buf, name = 'basedpyright' }[1]
local exclude = vim.tbl_get(client.settings or client.config.settings or {}, 'basedpyright', 'analysis', 'exclude') or {}
local has_build = false
for _, g in ipairs(exclude) do
  if g == '**/build' then has_build = true end
end
if has_build then
  print '  ok   server received **/build exclusion'
else
  print '  FAIL server did not receive **/build exclusion'
  vim.cmd 'cq 1'
end

-- Find an identifier to jump from: first symbol reported by the document.
local sym_res = client:request_sync('textDocument/documentSymbol', {
  textDocument = vim.lsp.util.make_text_document_params(buf),
}, 15000, buf)

local pos
if sym_res and sym_res.result and sym_res.result[1] then
  local first = sym_res.result[1]
  local range = first.selectionRange or first.range or (first.location and first.location.range)
  if range then pos = { line = range.start.line, character = range.start.character } end
end
pos = pos or { line = 0, character = 0 }
print(('  jumping from line %d col %d'):format(pos.line, pos.character))

-- Time three definition requests and take the median.
local times = {}
for i = 1, 3 do
  local t0 = vim.uv.hrtime()
  local res = client:request_sync('textDocument/definition', {
    textDocument = vim.lsp.util.make_text_document_params(buf),
    position = pos,
  }, BUDGET_MS * 4, buf)
  local ms = (vim.uv.hrtime() - t0) / 1e6
  times[#times + 1] = ms
  print(('  request %d: %.1f ms%s'):format(i, ms, (res and res.result) and '' or ' (no result)'))
end

table.sort(times)
local median = times[2]
print(('\nmedian gd latency: %.1f ms (budget %d ms)'):format(median, BUDGET_MS))

if median <= BUDGET_MS then
  print '  ok   gd latency within budget'
  vim.cmd 'cq 0'
else
  print(('  FAIL gd latency %.1f ms exceeds budget %d ms'):format(median, BUDGET_MS))
  vim.cmd 'cq 1'
end
```

- [ ] **Step 2: Run the test**

Run: `tests/run.sh gd`

Expected: PASS. The first run may be slow because basedpyright is installing
via Mason and performing an initial index; if it reports that basedpyright did
not attach, install it first:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -c 'MasonInstall basedpyright ruff' -c 'qa'
```

then re-run.

If the Brazil workspace is not mounted the test prints `SKIP` and exits 0.

- [ ] **Step 3: Record the result**

Note the median. This is the number to quote when reporting the fix, alongside
the startup measurement from Task 7.

- [ ] **Step 4: Commit**

```bash
git add tests/gd_latency.lua
git commit -m "test: add gd latency gate against real Brazil Python package"
```

---

## Task 12: Completion and formatting

**Files:**
- Create: `lua/plugins/completion.lua`
- Create: `lua/plugins/format.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== completion and formatting ==')
loads 'blink.cmp'
loads 'luasnip'
loads 'conform'
loads 'lint'

local conform_ok, conform = pcall(require, 'conform')
if conform_ok then
  local by_ft = conform.formatters_by_ft or {}
  for _, ft in ipairs { 'python', 'lua', 'rust', 'typescript', 'typescriptreact', 'json', 'sh' } do
    check('formatter for ' .. ft, by_ft[ft] ~= nil, 'none configured')
  end
end

check('format toggle mapped', has_nmap '<leader>uf')
check('format-on-save enabled by default', vim.g.autoformat ~= false)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'blink.cmp' not found`, `module 'conform' not
found`, and the formatter checks failing.

- [ ] **Step 3: Write the completion implementation**

Create `lua/plugins/completion.lua`:

```lua
-- blink.cmp: completion engine.
--
-- Chosen over nvim-cmp: it is faster, has fewer moving parts, and is where
-- momentum is. Pinned to major 1 for stability.

vim.pack.add {
  { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' },
  gh 'rafamadriz/friendly-snippets',
  { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' },
}

require('luasnip').setup {}
require('luasnip.loaders.from_vscode').lazy_load()

require('blink.cmp').setup {
  -- 'default' mirrors built-in ins-completion: <C-y> accepts, <C-n>/<C-p>
  -- cycle, <C-space> opens docs.
  keymap = { preset = 'default' },

  appearance = { nerd_font_variant = 'mono' },

  completion = {
    documentation = { auto_show = true, auto_show_delay_ms = 200 },
    ghost_text = { enabled = false },
    menu = { draw = { treesitter = { 'lsp' } } },
  },

  sources = {
    default = { 'lsp', 'path', 'snippets', 'buffer' },
  },

  snippets = { preset = 'luasnip' },

  -- The Rust matcher downloads a prebuilt binary and is substantially faster
  -- than the Lua implementation; fall back with a warning if unavailable.
  fuzzy = { implementation = 'prefer_rust_with_warning' },

  signature = { enabled = true },
}
```

- [ ] **Step 4: Write the formatting implementation**

Create `lua/plugins/format.lua`:

```lua
-- conform.nvim: formatting, with a format-on-save toggle.
--
-- The toggle matters because Brazil packages vary in convention and an
-- unexpected reformat creates noisy diffs in code review.

vim.pack.add { gh 'stevearc/conform.nvim' }

-- Default on. `vim.g.autoformat` is the global switch; `vim.b.autoformat`
-- overrides per buffer.
vim.g.autoformat = true

require('conform').setup {
  notify_on_error = false,

  format_on_save = function(bufnr)
    -- Buffer-local setting wins over the global one.
    local enabled = vim.b[bufnr].autoformat
    if enabled == nil then enabled = vim.g.autoformat end
    if not enabled then return nil end
    return { timeout_ms = 1000, lsp_format = 'fallback' }
  end,

  default_format_opts = { lsp_format = 'fallback' },

  formatters_by_ft = {
    lua = { 'stylua' },
    python = { 'ruff_fix', 'ruff_format' }, -- fix (incl. import sort) then format
    rust = { 'rustfmt' },
    javascript = { 'prettier' },
    javascriptreact = { 'prettier' },
    typescript = { 'prettier' },
    typescriptreact = { 'prettier' },
    json = { 'prettier' },
    jsonc = { 'prettier' },
    yaml = { 'prettier' },
    markdown = { 'prettier' },
    html = { 'prettier' },
    css = { 'prettier' },
    toml = { 'taplo' },
    sh = { 'shfmt' },
    bash = { 'shfmt' },
    go = { 'goimports', 'gofumpt' },
  },

  formatters = {
    shfmt = { prepend_args = { '-i', '2', '-ci' } },
  },
}

-- Linting.
--
-- Most linters in this config need no runner:
--   * ruff       -- runs as a language server (see lua/plugins/lsp.lua)
--   * clippy     -- rust-analyzer's checkOnSave (see lua/plugins/rust.lua)
--   * shellcheck -- bash-language-server invokes it natively
--   * eslint     -- vtsls surfaces it when the project configures it
--
-- markdownlint is the exception: it is CLI-only, so it needs nvim-lint to turn
-- its output into diagnostics. nvim-lint is the standard companion to conform
-- (same author's ecosystem, ~equally ubiquitous) and adds one autocmd.
vim.pack.add { gh 'mfussenegger/nvim-lint' }

local lint = require 'lint'
lint.linters_by_ft = { markdown = { 'markdownlint-cli2' } }

-- MD013 is the line-length rule. Prose here is soft-wrapped, so a hard column
-- limit is noise rather than signal. Passed on the command line so no
-- per-project config file is required.
local md = lint.linters['markdownlint-cli2']
if md then md.args = vim.list_extend({ '--config', vim.fn.stdpath 'config' .. '/.markdownlint-cli2.yaml' }, md.args or {}) end

vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
  desc = 'Run linters',
  group = vim.api.nvim_create_augroup('config-lint', { clear = true }),
  callback = function() require('lint').try_lint() end,
})

local map = vim.keymap.set

map({ 'n', 'v' }, '<leader>cf', function() require('conform').format { async = true } end, { desc = 'Format buffer' })

map('n', '<leader>uf', function()
  vim.g.autoformat = not vim.g.autoformat
  vim.notify('Format on save (global): ' .. (vim.g.autoformat and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle format on save (global)' })

map('n', '<leader>uF', function()
  local current = vim.b.autoformat
  if current == nil then current = vim.g.autoformat end
  vim.b.autoformat = not current
  vim.notify('Format on save (buffer): ' .. (vim.b.autoformat and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle format on save (buffer)' })
```

- [ ] **Step 5: Create the markdownlint config referenced by `format.lua`**

Create `.markdownlint-cli2.yaml` in the repo root:

```yaml
# Disable MD013 (line-length): prose here is soft-wrapped, so a hard column
# limit reports noise rather than real problems.
config:
  MD013: false
```

- [ ] **Step 6: Wire both into `init.lua`**

In `init.lua`, after `require 'plugins.explorer'`, add:

```lua
require 'plugins.completion'
require 'plugins.format'
```

- [ ] **Step 7: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS for all completion and formatting checks.

- [ ] **Step 8: Verify startup has not regressed**

Run: `tests/run.sh startup`

Expected: PASS, median under 60ms. If it fails, blink.cmp's Rust matcher may
be compiling on first run — re-run once and re-measure.

- [ ] **Step 9: Commit**

```bash
git add init.lua lua/plugins/completion.lua lua/plugins/format.lua .markdownlint-cli2.yaml tests/health.lua
git commit -m "feat: add blink.cmp completion, conform formatting and nvim-lint"
```

---

## Task 13: Git, Rust, DAP and testing plugins

**Files:**
- Create: `lua/plugins/git.lua`
- Create: `lua/plugins/rust.lua`
- Create: `after/ftplugin/rust.lua`
- Create: `lua/plugins/dap.lua`
- Create: `lua/plugins/test.lua`
- Modify: `init.lua`
- Test: `tests/health.lua` (extend)

- [ ] **Step 1: Write the failing test**

Add to `tests/health.lua` before the final `print`/`cq` lines:

```lua
print('== git, rust, dap, test ==')
loads 'gitsigns'
loads 'dap'
loads 'dapui'
loads 'neotest'

check('lazygit binary on PATH', vim.fn.executable 'lazygit' == 1)
check('rust-analyzer binary on PATH', vim.fn.executable 'rust-analyzer' == 1)

-- rustaceanvim configures itself through vim.g.rustaceanvim and must not be
-- setup()-ed. It owns rust_analyzer exclusively.
check('vim.g.rustaceanvim set', type(vim.g.rustaceanvim) == 'table', type(vim.g.rustaceanvim))

-- Use vim.lsp.is_enabled(), the supported query. There is no
-- `vim.lsp.config._enabled` field on 0.12 (it is nil), so testing against it
-- would silently always pass. Verified: is_enabled returns false for an
-- unknown server and true after vim.lsp.enable().
check(
  'rust_analyzer NOT enabled by this config (rustaceanvim owns it)',
  vim.lsp.is_enabled 'rust_analyzer' == false,
  'enabled by lsp.lua or mason-lspconfig -- would double-start'
)

for _, lhs in ipairs { '<leader>gg', '<leader>db', '<leader>tt' } do
  check('nmap ' .. lhs, has_nmap(lhs))
end
```

The `is_enabled` check is static: it proves this config never enabled
`rust_analyzer`. Task 14 Step 3 adds the complementary runtime check that
exactly one client actually attaches to a real Rust buffer.

- [ ] **Step 2: Run test to verify it fails**

Run: `tests/run.sh health`

Expected: FAIL with `module 'gitsigns' not found`, `module 'dap' not found`,
`module 'neotest' not found`, and the keymap checks failing.

- [ ] **Step 3: Write the git implementation**

Create `lua/plugins/git.lua`:

```lua
-- Git: inline hunk signs plus lazygit in a terminal.

vim.pack.add {
  gh 'lewis6991/gitsigns.nvim',
  gh 'nvim-lua/plenary.nvim', -- required by neotest and others
}

require('gitsigns').setup {
  signs = {
    add = { text = '┃' },
    change = { text = '┃' },
    delete = { text = '_' },
    topdelete = { text = '‾' },
    changedelete = { text = '~' },
    untracked = { text = '┆' },
  },
  on_attach = function(buf)
    local gs = require 'gitsigns'
    local function map(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc }) end

    map('n', ']h', function() gs.nav_hunk 'next' end, 'Next hunk')
    map('n', '[h', function() gs.nav_hunk 'prev' end, 'Previous hunk')
    map({ 'n', 'v' }, '<leader>ghs', gs.stage_hunk, 'Stage hunk')
    map({ 'n', 'v' }, '<leader>ghr', gs.reset_hunk, 'Reset hunk')
    map('n', '<leader>ghp', gs.preview_hunk, 'Preview hunk')
    map('n', '<leader>ghb', function() gs.blame_line { full = true } end, 'Blame line')
    map('n', '<leader>ghd', gs.diffthis, 'Diff this')
  end,
}

-- lazygit in a floating terminal. The binary is already installed.
vim.keymap.set('n', '<leader>gg', function()
  if vim.fn.executable 'lazygit' ~= 1 then
    vim.notify('lazygit not found on PATH', vim.log.levels.ERROR)
    return
  end

  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.9)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
  })

  vim.fn.jobstart({ 'lazygit' }, {
    term = true,
    on_exit = function()
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
      -- Refresh signs for changes made inside lazygit.
      pcall(function() require('gitsigns').refresh() end)
    end,
  })
  vim.cmd.startinsert()
end, { desc = 'Lazygit' })
```

- [ ] **Step 4: Write the Rust implementation**

Create `lua/plugins/rust.lua`:

```lua
-- rustaceanvim: rust-analyzer plus rust-analyzer-specific features that plain
-- LSP cannot express (grouped code actions, runnables, debuggables, macro
-- expansion, flyCheck).
--
-- Three constraints from its README:
--   1. There is NO setup() call. Configuration goes in vim.g.rustaceanvim and
--      must be set BEFORE the plugin initialises.
--   2. Config must NOT go in after/ftplugin/rust.lua -- that file loads after
--      initialisation. Keymaps do go there.
--   3. It owns rust_analyzer exclusively. Also running the lspconfig
--      rust_analyzer setup "may cause conflicts", which is why rust_analyzer
--      is absent from the servers table in lua/plugins/lsp.lua and
--      mason-lspconfig's automatic_enable is false.
--
-- Pinned to major 9: v9 requires Neovim 0.12, which this config targets.
-- Its README lists vim.pack first among install methods.

vim.g.rustaceanvim = {
  server = {
    default_settings = {
      ['rust-analyzer'] = {
        cargo = { allFeatures = true, buildScripts = { enable = true } },
        procMacro = { enable = true },
        checkOnSave = true,
        check = { command = 'clippy', extraArgs = { '--no-deps' } },
        inlayHints = {
          bindingModeHints = { enable = false },
          closureReturnTypeHints = { enable = 'never' },
          parameterHints = { enable = true },
        },
        files = {
          -- Keep rust-analyzer out of build output, including the Brazil
          -- build/ symlink.
          excludeDirs = { 'build', 'target', '.bemol', 'node_modules' },
        },
      },
    },
  },
  tools = {
    float_win_config = { border = 'rounded' },
  },
}

vim.pack.add {
  { src = gh 'mrcjkb/rustaceanvim', version = vim.version.range '^9' },
}
```

- [ ] **Step 5: Write the Rust ftplugin keymaps**

Create `after/ftplugin/rust.lua`:

```lua
-- rustaceanvim keymaps. Its README specifies that keymaps belong here, while
-- configuration must live in vim.g.rustaceanvim (set in lua/plugins/rust.lua)
-- because this file loads after the plugin initialises.

-- `K` and `<leader>ca` are intentionally re-mapped here, overriding the generic
-- versions set by the LspAttach handler in lua/plugins/lsp.lua. Both are
-- buffer-local and after/ftplugin runs later, so rustaceanvim's richer
-- implementations win in Rust buffers only. This is not a collision to "fix":
-- vim.lsp.buf.code_action cannot render rust-analyzer's grouped actions.
local buf = vim.api.nvim_get_current_buf()
local function map(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { buffer = buf, desc = desc }) end

-- Grouped code actions: vim.lsp.buf.code_action cannot render rust-analyzer's
-- action groups, so use rustaceanvim's own picker.
map('<leader>ca', function() vim.cmd.RustLsp 'codeAction' end, 'Code action (grouped)')
map('<leader>cR', function() vim.cmd.RustLsp 'runnables' end, 'Runnables')
map('<leader>cD', function() vim.cmd.RustLsp 'debuggables' end, 'Debuggables')
map('<leader>ce', function() vim.cmd.RustLsp 'explainError' end, 'Explain error')
map('<leader>cm', function() vim.cmd.RustLsp 'expandMacro' end, 'Expand macro')
map('<leader>cp', function() vim.cmd.RustLsp 'parentModule' end, 'Parent module')
map('<leader>cC', function() vim.cmd.RustLsp 'openCargo' end, 'Open Cargo.toml')
map('<leader>cdo', function() vim.cmd.RustLsp 'openDocs' end, 'Open docs.rs')
map('K', function() vim.cmd.RustLsp { 'hover', 'actions' } end, 'Hover actions')
```

- [ ] **Step 6: Write the DAP implementation**

Create `lua/plugins/dap.lua`:

```lua
-- Debugging. debugpy (Python) and codelldb (Rust) are installed via
-- mason-tool-installer in lua/plugins/lsp.lua.
--
-- Rust debugging is wired automatically by rustaceanvim, which detects
-- codelldb and builds DAP configurations itself.

vim.pack.add {
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio', -- required by dap-ui
  gh 'theHamsta/nvim-dap-virtual-text',
  gh 'mfussenegger/nvim-dap-python',
}

local dap = require 'dap'
local dapui = require 'dapui'

dapui.setup {}
require('nvim-dap-virtual-text').setup {}

-- Python. Point debugpy at Mason's copy so it works regardless of the
-- project's virtualenv.
local debugpy = vim.fn.stdpath 'data' .. '/mason/packages/debugpy/venv/bin/python'
if vim.fn.executable(debugpy) == 1 then
  require('dap-python').setup(debugpy)
else
  -- Fall back to whatever python3 is active.
  require('dap-python').setup 'python3'
end

-- Open and close the UI automatically with the debug session.
dap.listeners.after.event_initialized['dapui'] = function() dapui.open {} end
dap.listeners.before.event_terminated['dapui'] = function() dapui.close {} end
dap.listeners.before.event_exited['dapui'] = function() dapui.close {} end

-- Breakpoint signs.
vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DiagnosticError' })
vim.fn.sign_define('DapStopped', { text = '▶', texthl = 'DiagnosticWarn', linehl = 'Visual' })

local map = vim.keymap.set
map('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Toggle breakpoint' })
map('n', '<leader>dB', function() dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, { desc = 'Conditional breakpoint' })
map('n', '<leader>dc', dap.continue, { desc = 'Continue' })
map('n', '<leader>di', dap.step_into, { desc = 'Step into' })
map('n', '<leader>do', dap.step_over, { desc = 'Step over' })
map('n', '<leader>dO', dap.step_out, { desc = 'Step out' })
map('n', '<leader>dt', dap.terminate, { desc = 'Terminate' })
map('n', '<leader>dr', dap.repl.toggle, { desc = 'Toggle REPL' })
map('n', '<leader>du', function() dapui.toggle {} end, { desc = 'Toggle debug UI' })
```

- [ ] **Step 7: Write the testing implementation**

Create `lua/plugins/test.lua`:

```lua
-- neotest: run and debug individual tests from the buffer.
--
-- Python uses the pytest adapter. Rust needs no adapter here: rustaceanvim
-- ships its own neotest adapter, which it registers when a Rust buffer opens.

vim.pack.add {
  gh 'nvim-neotest/neotest',
  gh 'nvim-neotest/neotest-python',
  gh 'nvim-neotest/nvim-nio',
  gh 'antoinemadec/FixCursorHold.nvim',
}

local adapters = {
  require 'neotest-python' {
    dap = { justMyCode = false },
    runner = 'pytest',
  },
}

-- rustaceanvim exposes its adapter as a module; include it when present.
local ok_rust, rust_adapter = pcall(function() return require 'rustaceanvim.neotest' end)
if ok_rust then table.insert(adapters, rust_adapter) end

require('neotest').setup {
  adapters = adapters,
  discovery = {
    -- Discovery walks the filesystem; disabling it avoids scanning the Brazil
    -- build/ symlink. Tests are still found in the current file on demand.
    enabled = false,
  },
  status = { virtual_text = true },
  output = { open_on_run = false },
}

local nt = require 'neotest'
local map = vim.keymap.set
map('n', '<leader>tt', function() nt.run.run() end, { desc = 'Run nearest test' })
map('n', '<leader>tf', function() nt.run.run(vim.fn.expand '%') end, { desc = 'Run file tests' })
map('n', '<leader>tl', function() nt.run.run_last() end, { desc = 'Run last test' })
map('n', '<leader>td', function() nt.run.run { strategy = 'dap' } end, { desc = 'Debug nearest test' })
map('n', '<leader>ts', function() nt.summary.toggle() end, { desc = 'Toggle test summary' })
map('n', '<leader>to', function() nt.output.open { enter = true } end, { desc = 'Show test output' })
map('n', '<leader>tS', function() nt.run.stop() end, { desc = 'Stop test run' })
```

- [ ] **Step 8: Wire them all into `init.lua`**

In `init.lua`, after `require 'plugins.format'`, add:

```lua
require 'plugins.git'
require 'plugins.rust'
require 'plugins.dap'
require 'plugins.test'
```

- [ ] **Step 9: Run test to verify it passes**

Run: `tests/run.sh health`

Expected: PASS for all checks.

- [ ] **Step 10: Commit**

```bash
git add init.lua lua/plugins/git.lua lua/plugins/rust.lua lua/plugins/dap.lua lua/plugins/test.lua after/ftplugin/rust.lua tests/health.lua
git commit -m "feat: add git, rustaceanvim, DAP and neotest"
```

---

## Task 14: Remove kickstart scaffolding and verify end to end

**Files:**
- Delete: `lua/kickstart/plugins/autopairs.lua`, `debug.lua`, `gitsigns.lua`, `indent_line.lua`, `lint.lua`, `neo-tree.lua`
- Delete: `lua/custom/plugins/init.lua`
- Modify: `README.md`

- [ ] **Step 1: Confirm nothing references the files about to be deleted**

```bash
grep -rn "kickstart.plugins\|custom.plugins" init.lua lua/ after/ tests/ || echo "no references - safe to delete"
```

Expected: `no references - safe to delete`. If anything is printed, remove the
reference before continuing.

- [ ] **Step 2: Delete the scaffolding**

```bash
git rm -r lua/kickstart/plugins lua/custom
```

`lua/kickstart/health.lua` is deliberately kept — Task 15 extends it.

- [ ] **Step 3: Verify one rust_analyzer client attaches, not two**

This is the check the health test cannot fully make statically.

```bash
NVIM_APPNAME=nvim-dev nvim --headless \
  ~/workplace/PanoramaMCP/src/PanoramaMCP/src/main.rs \
  -c 'sleep 15' \
  -c 'lua local n=0; for _,c in ipairs(vim.lsp.get_clients()) do if c.name:match("rust") then n=n+1; print("client: "..c.name) end end; print("rust clients: "..n)' \
  -c 'qa' 2>&1 | tail -5
```

Expected: exactly one client, named `rustaceanvim` or `rust_analyzer`, and
`rust clients: 1`. If it reports 2, the double-enable regression has occurred —
check that `automatic_enable = false` in `lua/plugins/lsp.lua` and that
`rust_analyzer` is not in the `servers` table.

If no `.rs` file exists at that path, find one:
`find ~/workplace -name '*.rs' -not -path '*/target/*' | head -1`

- [ ] **Step 4: Run the whole suite**

Run: `tests/run.sh`

Expected: all three suites PASS. Record the startup median and `gd` median.

- [ ] **Step 5: Interactive smoke test**

Open each language and confirm real behaviour by hand:

```bash
NVIM_APPNAME=nvim-dev nvim ~/workplace/Qualo/src/Qualo/src/backend_lambda/main.py
```

Check, in order:
1. `gd` on a function call jumps without a visible delay
2. `K` shows hover documentation
3. Typing triggers completion
4. `]d` moves to a diagnostic and shows it as virtual lines
5. `gK` toggles virtual lines off and on
6. `<leader>ca` opens code actions
7. `:w` reformats via ruff
8. `<leader>ff`, `<leader>fg`, `<leader>e` all open

Repeat for a TypeScript file, a Rust file, and `init.lua` itself.

- [ ] **Step 6: Update the README**

Replace `README.md` with:

```markdown
# Neovim config

Fast, modular Neovim config for Python, TypeScript, Rust, Go, Lua, Bash and
friends. Built on Neovim 0.12's built-in `vim.pack` plugin manager.

Design and rationale: `docs/superpowers/specs/2026-07-30-nvim-config-design.md`

## Requirements

Neovim >= 0.12, git, make, a C compiler, `rg`, `fd`, `fzf`, a Nerd Font.
Optional: `lazygit`, `cargo`, `go`, `node`.

## Layout

| Path | Contents |
|---|---|
| `init.lua` | Leader keys, build hooks, module requires |
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

## Performance notes

Two things must not be reintroduced, both measured causes of multi-second
`gd` latency in the previous config:

1. **No reference-counting codelens.** Anything issuing
   `textDocument/references` on `CursorMoved` puts whole-workspace scans ahead
   of your definition requests on a single-threaded server.
2. **Keep the Brazil excludes.** `lua/config/brazil.lua` excludes `build/`,
   which is a cross-volume symlink into the build farm containing thousands of
   files.

Only one component may own each language server. `lua/plugins/lsp.lua` owns
all of them except `rust_analyzer`, which belongs to rustaceanvim; this is why
`mason-lspconfig`'s `automatic_enable` is `false`.
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: remove kickstart scaffolding and update README"
```

---

## Task 15: Extend the health check

**Files:**
- Modify: `lua/kickstart/health.lua` → move to `lua/config/health.lua`

- [ ] **Step 1: Move and rewrite the health module**

```bash
git mv lua/kickstart/health.lua lua/config/health.lua
```

Replace its contents with:

```lua
-- :checkhealth config
--
-- Verifies external tools and the two performance invariants described in
-- README.md.

local M = {}

local function check_neovim()
  local verstr = tostring(vim.version())
  if vim.version.ge(vim.version(), '0.12') then
    vim.health.ok(('Neovim version %s'):format(verstr))
  else
    vim.health.error(('Neovim %s is too old; this config requires 0.12+ (vim.pack)'):format(verstr))
  end
end

local function check_externals()
  local required = { 'git', 'rg', 'fd', 'fzf' }
  local optional = { 'make', 'cc', 'lazygit', 'cargo', 'rust-analyzer', 'go', 'node', 'npm', 'python3' }

  for _, exe in ipairs(required) do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(('found %s'):format(exe))
    else
      vim.health.error(('missing %s (required)'):format(exe))
    end
  end

  for _, exe in ipairs(optional) do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(('found %s'):format(exe))
    else
      vim.health.warn(('missing %s (optional)'):format(exe))
    end
  end
end

local function check_diagnostics_config()
  local cfg = vim.diagnostic.config()
  if type(cfg.virtual_text) == 'table' and cfg.virtual_text.current_line == false and type(cfg.virtual_lines) == 'table' then
    vim.health.ok 'hybrid diagnostics active (virtual_text off-cursor, virtual_lines on-cursor)'
  else
    vim.health.warn 'hybrid diagnostics not configured as designed; see lua/config/diagnostics.lua'
  end
end

local function check_no_codelens()
  -- Reference-counting codelens was a measured cause of gd latency.
  local offenders = { 'lensline', 'lsp_lines', 'nvim-lightbulb' }
  local found = {}
  for _, name in ipairs(offenders) do
    if package.loaded[name] then found[#found + 1] = name end
  end
  if #found == 0 then
    vim.health.ok 'no reference-counting codelens plugins loaded'
  else
    vim.health.error(('codelens plugin(s) loaded: %s -- these queue whole-workspace LSP requests ahead of gd'):format(table.concat(found, ', ')))
  end
end

local function check_brazil_excludes()
  local ok, brazil = pcall(require, 'config.brazil')
  if not ok then
    vim.health.error 'config.brazil failed to load'
    return
  end
  if vim.tbl_contains(brazil.exclude_globs, '**/build') then
    vim.health.ok 'Brazil build/ exclusion present'
  else
    vim.health.error 'Brazil build/ exclusion missing -- language servers will index the build farm'
  end
end

local function check_single_lsp_owner()
  local ok, settings = pcall(require, 'mason-lspconfig.settings')
  if not ok then
    vim.health.warn 'mason-lspconfig settings unavailable'
    return
  end
  if settings.current.automatic_enable == false then
    vim.health.ok 'mason-lspconfig automatic_enable is false (this config owns enablement)'
  else
    vim.health.error 'mason-lspconfig automatic_enable is on -- servers may be configured twice, overriding tuned settings'
  end
end

function M.check()
  vim.health.start 'config: environment'
  check_neovim()
  check_externals()

  vim.health.start 'config: performance invariants'
  check_diagnostics_config()
  check_no_codelens()
  check_brazil_excludes()
  check_single_lsp_owner()
end

return M
```

- [ ] **Step 2: Run the health check**

```bash
NVIM_APPNAME=nvim-dev nvim --headless -c 'checkhealth config' -c 'qa' 2>&1 | head -40
```

Expected: `config: environment` and `config: performance invariants` sections,
with OK for all four invariants. Warnings for genuinely missing optional tools
(`prettier`, `taplo` before Mason installs them) are fine; errors are not.

- [ ] **Step 3: Run the full suite once more**

Run: `tests/run.sh`

Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add health check for performance invariants"
```

---

## Task 16: Cutover (requires explicit user approval)

**Do not start this task without the user explicitly approving the cutover.**
Everything before this point leaves `~/.config/nvim` untouched.

**Files:** none in the repo — this changes the user's environment.

- [ ] **Step 1: Report measurements and ask for approval**

Report to the user:
- startup median (baseline was 170–280ms)
- `gd` latency median from `tests/gd_latency.lua`
- confirmation that `tests/run.sh` passes and `:checkhealth config` is clean

Then ask whether to cut over. **Stop here until they answer.**

- [ ] **Step 2: Back up the existing config**

```bash
mv ~/.config/nvim ~/.config/nvim-lazyvim-backup
ls -d ~/.config/nvim-lazyvim-backup
```

The LazyVim data directory at `~/.local/share/nvim` is left in place, so the
backup remains fully working.

- [ ] **Step 3: Symlink the new config**

```bash
ln -sfn /Users/abelor/projects/nvim ~/.config/nvim
readlink ~/.config/nvim
```

Expected: `/Users/abelor/projects/nvim`

- [ ] **Step 4: Verify as the default config**

```bash
nvim --headless -c 'checkhealth config' -c 'qa' 2>&1 | head -30
nvim --headless --startuptime /tmp/final.log -c 'qa' && tail -1 /tmp/final.log
```

Expected: health clean; startup comparable to the `nvim-dev` measurement.

Then open a real file interactively and confirm `gd` is fast:

```bash
nvim ~/workplace/Qualo/src/Qualo/src/backend_lambda/main.py
```

- [ ] **Step 5: Document the rollback**

Tell the user how to revert if anything is wrong:

```bash
rm ~/.config/nvim && mv ~/.config/nvim-lazyvim-backup ~/.config/nvim
```

The backup and its data directory are untouched, so this restores the previous
setup exactly.

---

## Optional follow-up (not part of this plan)

Two items were explicitly ruled out of scope in the spec and should only be
picked up if the user asks:

1. **`smithy-language-server`** — Smithy currently gets treesitter
   highlighting only. Adding the JVM-based server would give completion and
   go-to-definition on shapes across 54 model files.
2. **Fixing the old LazyVim install** — deleting
   `~/.config/nvim/lua/plugins/lensline.lua` and adding the `exclude` globs to
   its pyright config would fix `gd` there too, which is worth doing if the
   backup is ever used as a fallback.
