# Quality-of-Life Plugin Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the quality-of-life layer this config lacks (autopairing, indent guides, big-file guard, function/class textobjects, Lua API completion, sessions, multi-file replace, bracket navigation) without exceeding the 125 ms startup budget.

**Architecture:** One new file `lua/plugins/editor.lua` owns the QoL layer, keeping `ui.lua` about appearance. Only snacks.nvim (~4.4 ms, measured) and lazydev (~1 ms, ftplugin-gated) load eagerly; everything else uses the deferral pattern documented in `lua/plugins/completion.lua` — do not call `vim.pack.add` until first use, because `{ load = false }` still lands a plugin on runtimepath and Neovim sources its `plugin/` files later in the same startup.

**Tech Stack:** Neovim 0.12, `vim.pack`, Lua. snacks.nvim, mini.pairs, mini.indentscope (mini.nvim already on disk), nvim-treesitter-textobjects (`main`), lazydev.nvim, persistence.nvim, grug-far.nvim.

**Spec:** `docs/superpowers/specs/2026-07-31-qol-plugins-design.md`

---

## Testing model for this repo

There is no unit-test framework here. `tests/health.lua` is an assertion suite run by `tests/run.sh`, which supplies the mandatory `-u` flag. TDD therefore means: **add the health assertion, run the suite and watch it fail, implement, watch it pass.**

Run the whole suite with:

```bash
tests/run.sh
```

Run just the assertion suite (faster inner loop):

```bash
tests/run.sh health
```

`tests/run.sh startup` is the real regression gate for this plan — it asserts the
125 ms budget. Run it after every task that adds an eager plugin.

Two harness facts that matter when writing assertions:

- The suite runs headless, so no Rust/Python buffer exists and no LSP attaches.
  Anything buffer-triggered must be asserted **statically** (config table or
  source text), not by live state.
- `vim.g.*` assertions can pass vacuously. When an assertion reads a config
  table, also confirm it fails with the feature removed (each task below has an
  explicit "verify it fails" step).

Formatting: this repo uses stylua with `.stylua.toml`. `stylua` is installed via
Mason, so use the Mason binary:

```bash
~/.local/share/nvim/mason/bin/stylua --check <files>
```

If that path does not exist, run `:MasonToolsInstall` inside Neovim first, or
skip the format check — `tests/run.sh` does not enforce it.

---

## Task 1: Create `lua/plugins/editor.lua` with snacks.nvim

Adds the big-file guard, fast first render, notification popups and a better
`vim.ui.input`. This is the one new eager plugin; it cannot be deferred because
`bigfile` hooks `BufReadPre` and `quickfile` exists to render before plugins load.

**Files:**
- Create: `lua/plugins/editor.lua`
- Modify: `init.lua` (add the require)
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertions**

Add to `tests/health.lua`, immediately before the line `print '== completion and formatting =='`:

```lua
print '== editor QoL =='
loads 'snacks'

-- snacks is the one new eager plugin. Only these four modules are wanted:
-- picker/explorer duplicate telescope and nvim-tree, statuscolumn and dashboard
-- are cosmetic, and scroll/words add per-motion and per-CursorHold work (words
-- also duplicates the documentHighlight autocmd in lsp.lua).
-- NOTE on reading snacks.config: its config table has an __index metatable that
-- auto-creates an empty table for any key touched (its init.lua:49-53), so
-- `snacks.config.picker` is NEVER nil. Verified. Assert on `.enabled` only --
-- testing the table for nil would always pass and prove nothing.
local snacks_ok, snacks = pcall(require, 'snacks')
if snacks_ok then
  for _, m in ipairs { 'bigfile', 'quickfile', 'notifier', 'input' } do
    check('snacks.' .. m .. ' enabled', snacks.config[m].enabled == true)
  end
  for _, m in ipairs { 'picker', 'explorer', 'dashboard', 'scroll', 'words', 'statuscolumn' } do
    check('snacks.' .. m .. ' NOT enabled', snacks.config[m].enabled ~= true, 'duplicates existing plugins or adds per-keystroke work')
  end
  -- Indent guides must have exactly one owner; mini.indentscope owns them
  -- (Task 3). Both drawing at once produces overlapping extmarks and flicker.
  check('snacks.indent NOT enabled (mini.indentscope owns guides)', snacks.config.indent.enabled ~= true)

  -- vim.notify must be REPLACED. Comparing directly against notifier.notify
  -- fails on a fresh session: snacks installs a one-shot trampoline that only
  -- swaps itself out on the first call (its init.lua:219-223). Verified both
  -- ways. So fire one notification first, then compare.
  vim.notify('health check', vim.log.levels.INFO)
  check('notifier took over vim.notify', vim.notify == require('snacks.notifier').notify)
end
```

- [ ] **Step 2: Run the suite to verify the new assertions fail**

```bash
tests/run.sh health
```

Expected: `FAIL require snacks` (the `loads 'snacks'` line), and the per-module
checks are skipped because `snacks_ok` is false. The suite exits 1.

- [ ] **Step 3: Create `lua/plugins/editor.lua`**

```lua
-- Quality-of-life editor plugins: big-file guard, autopairing, indent guides,
-- sessions and project-wide replace.
--
-- Kept separate from lua/plugins/ui.lua, which owns appearance (colorscheme,
-- statusline, icons). This file owns behaviour.

-- snacks.nvim -- THE ONE NEW EAGER PLUGIN, and it cannot be deferred.
--
-- `bigfile` has to be registered before the BufReadPre that opens the file it is
-- meant to guard, and `quickfile` exists specifically to render a buffer BEFORE
-- plugins load. Deferring either defeats its purpose.
--
-- Affordable because Snacks.setup() only creates autocmds: every submodule sits
-- behind an __index metatable that requires on demand (its init.lua builds one
-- augroup with a `once` autocmd per event group). Measured cold, 3 runs:
-- 5.50 / 4.40 / 4.34 ms, 4 modules added.
--
-- Scope is deliberately four modules. Rejected: picker and explorer (duplicate
-- telescope and nvim-tree), statuscolumn and dashboard (cosmetic), scroll and
-- words (per-motion and per-CursorHold work; `words` duplicates the
-- documentHighlight autocmd in lua/plugins/lsp.lua), and indent (mini.indentscope
-- owns guides -- enabling both draws overlapping extmarks and flickers).
vim.pack.add { gh 'folke/snacks.nvim' }

require('snacks').setup {
  -- Stops treesitter and the LSP attaching to generated or minified files.
  -- This config had no large-file guard at all before.
  bigfile = { enabled = true },

  -- Renders the file before plugins finish loading, for `nvim <file>`.
  quickfile = { enabled = true },

  -- Replaces vim.notify. The ~8 existing call sites (VenvSelect, the format
  -- toggles, lazygit) become stacked auto-dismissing popups instead of
  -- :messages lines you have to go looking for.
  notifier = { enabled = true, timeout = 3000 },

  -- Replaces vim.ui.input. No conflict with the telescope ui-select extension
  -- in lua/plugins/picker.lua: vim.ui.input and vim.ui.select are separate hooks.
  input = { enabled = true },
}

vim.keymap.set('n', '<leader>n', function() require('snacks').notifier.show_history() end, { desc = 'Notification history' })
vim.keymap.set('n', '<leader>un', function() require('snacks').notifier.hide() end, { desc = 'Dismiss notifications' })
```

- [ ] **Step 4: Require it from `init.lua`**

In `init.lua`, find the block of `require 'plugins.*'` lines. After the
`require 'plugins.ui'` line, add:

```lua
require 'plugins.editor'
```

- [ ] **Step 5: Run the suite to verify the assertions pass**

```bash
tests/run.sh health
```

Expected: all `snacks.*` checks `ok`, `0 failure(s)`, exit 0.

- [ ] **Step 6: Verify the startup budget still holds**

```bash
tests/run.sh startup
```

Expected: median under 125 ms (projected ~100 ms). If it exceeds the budget,
stop and report — do not raise the budget.

- [ ] **Step 7: Prove the assertion is not vacuous**

Temporarily change `notifier = { enabled = true, timeout = 3000 }` to
`notifier = { enabled = false }` in `lua/plugins/editor.lua`, then:

```bash
tests/run.sh health
```

Expected: `FAIL snacks.notifier enabled` and `FAIL notifier replaced vim.notify`.
Restore `enabled = true, timeout = 3000` and re-run to confirm green.

- [ ] **Step 8: Commit**

```bash
git add lua/plugins/editor.lua init.lua tests/health.lua
git commit -m "feat(editor): add snacks.nvim (bigfile, quickfile, notifier, input)"
```

---

## Task 2: mini.pairs — autopairing

The largest genuine gap: #16 most-installed plugin, and this config had no
autopairing at all. mini.nvim is already on disk and eagerly loaded, so this is
one `setup()` call inside the existing deferred autocmd — zero startup cost.

**Files:**
- Modify: `lua/plugins/ui.lua` (the `BufReadPost`/`BufNewFile` autocmd, around line 80-95)
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertion**

Add to `tests/health.lua`, at the end of the `== editor QoL ==` section added in
Task 1:

```lua
-- mini.pairs is set up on the first real buffer (lua/plugins/ui.lua), which the
-- headless suite has none of -- so assert the source wires it, not live state.
local ui_src = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/ui.lua', 'r')
if ui_src then
  local src = ui_src:read 'a'
  ui_src:close()
  check('mini.pairs set up on first buffer', src:match "require%('mini%.pairs'%)%.setup" ~= nil)
  -- Command mode on, terminal off: pairs on the `:` line are useful, pairs in a
  -- shell or lazygit terminal are not.
  check('mini.pairs command mode on, terminal off', src:match 'command = true' ~= nil and src:match 'terminal = false' ~= nil)
end
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: `FAIL mini.pairs set up on first buffer` and
`FAIL mini.pairs command mode on, terminal off`.

- [ ] **Step 3: Add the setup call**

In `lua/plugins/ui.lua`, inside the `BufReadPost`/`BufNewFile` autocmd callback,
after the existing `require('mini.surround').setup()` line, add:

```lua
    -- Autopairing. Free here: mini.nvim is already loaded, so this is one
    -- setup() call rather than a new plugin.
    --
    -- ON <CR>, which the usual advice gets wrong for this config. blink.cmp's
    -- `default` preset does NOT map <CR> -- it accepts on <C-y>, mirroring
    -- built-in ins-completion (see lua/plugins/completion.lua). Probed live:
    -- with blink loaded, maparg('<CR>', 'i') is empty and mini.pairs then
    -- installs v:lua.MiniPairs.cr(). mini.pairs also guards this itself, only
    -- mapping <CR> when maparg is empty (its pairs.lua:557), so it yields to any
    -- future binding. Keeping it is what puts the cursor on a properly indented
    -- blank line when you press Enter between { and }.
    require('mini.pairs').setup {
      -- Command mode included so pairs work on the `:` line. Terminal excluded
      -- so they never interfere with a shell or lazygit.
      modes = { insert = true, command = true, terminal = false },
    }
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: both `mini.pairs` checks `ok`, `0 failure(s)`.

- [ ] **Step 5: Verify the behaviour end to end**

The assertions are static, so confirm the real interaction once. Write this
probe to `/tmp/pairs_probe.lua`:

```lua
-- Confirms mini.pairs loads on a real buffer, owns <CR>, and that blink still
-- accepts on <C-y> rather than <CR>.
local f = vim.fn.tempname() .. '.lua'
vim.fn.writefile({ 'local t = ' }, f)
vim.cmd.edit(f)
vim.cmd 'doautocmd BufReadPost'
print('mini.pairs loaded: ' .. tostring(package.loaded['mini.pairs'] ~= nil))

vim.cmd 'doautocmd InsertEnter'
vim.wait(3000, function() return package.loaded['blink.cmp'] ~= nil end, 50)
print('blink loaded: ' .. tostring(package.loaded['blink.cmp'] ~= nil))

local cr = vim.fn.maparg('<CR>', 'i')
print('<CR> owner: ' .. (cr == '' and '(unmapped)' or cr))
print('open paren mapped: ' .. tostring(vim.fn.maparg('(', 'i') ~= ''))
```

Run it:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -u "$HOME/.config/nvim-dev/init.lua" -l /tmp/pairs_probe.lua
```

Expected: `mini.pairs loaded: true`, `blink loaded: true`,
`<CR> owner: v:lua.MiniPairs.cr()`, `open paren mapped: true`.

Then clean up: `rm /tmp/pairs_probe.lua`

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/ui.lua tests/health.lua
git commit -m "feat(editor): add mini.pairs autopairing"
```

---

## Task 3: mini.indentscope — indent guides

Also free (mini.nvim already loaded). Owns indent guides exclusively;
`snacks.indent` stays off, asserted in Task 1.

**Files:**
- Modify: `lua/plugins/ui.lua` (same autocmd as Task 2)
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertion**

Append to the `== editor QoL ==` section in `tests/health.lua`. This reuses the
`ui.lua` source read from Task 2, so add it inside that same `if ui_src then`
block, after the `mini.pairs` checks:

```lua
  check('mini.indentscope set up on first buffer', src:match "require%('mini%.indentscope'%)%.setup" ~= nil)
  -- Guides in a help/terminal/tree buffer are noise, not signal.
  check('mini.indentscope disabled in scratch filetypes', src:match 'MiniIndentscopeDisable' ~= nil)
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: `FAIL mini.indentscope set up on first buffer` and
`FAIL mini.indentscope disabled in scratch filetypes`.

- [ ] **Step 3: Add the setup call and the per-filetype disable**

In `lua/plugins/ui.lua`, in the same autocmd callback, after the `mini.pairs`
block added in Task 2:

```lua
    -- Indent guides. Owns them exclusively -- snacks.indent stays off, because
    -- two plugins drawing extmarks in the same columns flickers.
    require('mini.indentscope').setup {
      -- Default is an animated draw; instant keeps it from competing with
      -- cursor movement on large files.
      draw = { delay = 50, animation = require('mini.indentscope').gen_animation.none() },
      symbol = '│',
      options = { try_as_border = true },
    }
```

Then, still in `lua/plugins/ui.lua`, after the closing `})` of that autocmd, add
a separate autocmd:

```lua
-- Indent guides are noise in throwaway and UI buffers. mini.indentscope reads
-- this buffer-local variable on each draw.
vim.api.nvim_create_autocmd('FileType', {
  desc = 'Disable indent guides in scratch and UI buffers',
  group = deferred,
  pattern = { 'help', 'man', 'qf', 'lspinfo', 'checkhealth', 'trouble', 'NvimTree', 'gitcommit', 'markdown', 'snacks_notif', 'snacks_terminal' },
  callback = function(ev) vim.b[ev.buf].miniindentscope_disable = true end,
})

-- Terminal buffers have no meaningful indent structure.
vim.api.nvim_create_autocmd('TermOpen', {
  desc = 'Disable indent guides in terminals',
  group = deferred,
  callback = function(ev) vim.b[ev.buf].miniindentscope_disable = true end,
})
```

Note: the assertion in Step 1 searches for the string `MiniIndentscopeDisable`,
but the variable above is `miniindentscope_disable`. Use this assertion instead
— replace the second check from Step 1 with:

```lua
  check('mini.indentscope disabled in scratch filetypes', src:match 'miniindentscope_disable' ~= nil)
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: both `mini.indentscope` checks `ok`, `0 failure(s)`.

- [ ] **Step 5: Confirm no startup regression**

```bash
tests/run.sh startup
```

Expected: still under 125 ms. mini.nvim was already loaded, so this should not
move the number.

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/ui.lua tests/health.lua
git commit -m "feat(ui): add mini.indentscope indent guides"
```

---

## Task 4: nvim-treesitter-textobjects — function and class textobjects

Closes the gap where no textobject selects a whole function body or class.
`mini.ai`'s builtin `f` is function *call*, not definition.

**Files:**
- Modify: `lua/plugins/treesitter.lua`
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertions**

Append to the `== editor QoL ==` section in `tests/health.lua`:

```lua
-- Function/class textobjects. nvim-treesitter's main branch ships no
-- textobjects.scm (verified: 0 files); the companion repo carries its own
-- queries -- confirmed present for rust (15 fn/class captures), python, lua, go
-- and typescript.
loads 'nvim-treesitter-textobjects'

-- Neovim's own ftplugin/python.vim maps ]m and [m buffer-locally in n/o/x modes
-- (its lines 64-83), which would shadow these globals in the most-used language
-- here. Opt out per filetype rather than with the README's global
-- no_plugin_maps, which would disable ftplugin maps across all 29 filetypes
-- that honour it.
check('python ftplugin maps disabled (]m would be shadowed)', vim.g.no_python_maps == true)
check('ruby ftplugin maps disabled', vim.g.no_ruby_maps == true)

-- Upstream key scheme: am/im for functions (m = method), ac/ic for classes.
-- Leaves mini.ai's `f` (function-call) untouched, so no remap is needed.
for _, lhs in ipairs { 'am', 'im', 'ac', 'ic' } do
  local found = false
  for _, m in ipairs(vim.api.nvim_get_keymap 'o') do
    if m.lhs == lhs then found = true end
  end
  check('operator-pending textobject ' .. lhs, found)
end
for _, lhs in ipairs { ']m', '[m', ']c', '[c' } do
  check('movement ' .. lhs, has_nmap(lhs))
end
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: `FAIL require nvim-treesitter-textobjects`,
`FAIL python ftplugin maps disabled`, and all eight keymap checks fail.

- [ ] **Step 3: Add the plugin and keymaps**

Append to `lua/plugins/treesitter.lua`:

```lua
-- FUNCTION AND CLASS TEXTOBJECTS.
--
-- mini.ai's builtin set (its H.builtin_textobjects) is
-- ( [ { < ' " ` ? a b f t q -- where `f` is function CALL, not function
-- DEFINITION. So nothing selected a whole function body or a class before this.
--
-- The `main` branch is required to match the nvim-treesitter pin above, and it
-- is this repo's default branch. Note nvim-treesitter's own main branch ships NO
-- textobjects.scm (verified: zero files across all languages) -- these queries
-- come from this companion repo, which carries them for every language in use
-- here: rust (15 function/class captures), python, lua, go, typescript.
--
-- The main branch has no module system: setup() takes behavioural options only
-- and every keymap is defined by hand below.
vim.pack.add {
  { src = gh 'nvim-treesitter/nvim-treesitter-textobjects', version = 'main' },
}

-- MAP CONFLICT. Neovim's own ftplugin/python.vim maps ]m and [m buffer-locally
-- across n/o/x modes (its lines 64-83), which would silently shadow the global
-- maps below in the language used most here. The plugin's README suggests
-- `vim.g.no_plugin_maps = true`, but that disables ftplugin maps for all 29
-- filetypes that honour the convention. Opt out only for the filetypes actually
-- affected.
--
-- Must be set before the ftplugin runs, which is why it is here rather than in
-- an autocmd.
vim.g.no_python_maps = true
vim.g.no_ruby_maps = true

require('nvim-treesitter-textobjects').setup {
  select = {
    -- Jump forward to the next textobject when the cursor is not inside one,
    -- like targets.vim.
    lookahead = true,
    selection_modes = {
      ['@function.outer'] = 'V', -- linewise: a function is a block of lines
      ['@class.outer'] = 'V',
      ['@parameter.outer'] = 'v', -- charwise: an argument is inline
    },
    include_surrounding_whitespace = false,
  },
  move = { set_jumps = true }, -- so <C-o> comes back
}

local select = require 'nvim-treesitter-textobjects.select'
local move = require 'nvim-treesitter-textobjects.move'
local swap = require 'nvim-treesitter-textobjects.swap'

-- UPSTREAM KEY SCHEME, not LazyVim's.
--
-- `am`/`im` for functions (m = method) and `ac`/`ic` for classes. LazyVim uses
-- af/if for functions, but `f` is already mini.ai's function-call textobject
-- (configured in lua/plugins/ui.lua); the upstream scheme avoids a remap and
-- keeps both available.
local function sel(capture, group)
  return function() select.select_textobject(capture, group or 'textobjects') end
end

for lhs, capture in pairs {
  am = '@function.outer',
  im = '@function.inner',
  ac = '@class.outer',
  ic = '@class.inner',
  ['a='] = '@assignment.outer',
  ['i='] = '@assignment.inner',
} do
  vim.keymap.set({ 'x', 'o' }, lhs, sel(capture), { desc = 'Textobject ' .. capture })
end

-- Movement. Capital variants go to the END of the object, matching the ]] / ][
-- convention.
for lhs, spec in pairs {
  [']m'] = { move.goto_next_start, '@function.outer' },
  [']M'] = { move.goto_next_end, '@function.outer' },
  ['[m'] = { move.goto_previous_start, '@function.outer' },
  ['[M'] = { move.goto_previous_end, '@function.outer' },
  [']c'] = { move.goto_next_start, '@class.outer' },
  ['[c'] = { move.goto_previous_start, '@class.outer' },
} do
  local fn, capture = spec[1], spec[2]
  vim.keymap.set({ 'n', 'x', 'o' }, lhs, function() fn(capture, 'textobjects') end, { desc = 'Goto ' .. capture })
end

-- Swap arguments -- the single most useful of these in practice.
vim.keymap.set('n', ']a', function() swap.swap_next '@parameter.inner' end, { desc = 'Swap parameter next' })
vim.keymap.set('n', '[a', function() swap.swap_previous '@parameter.inner' end, { desc = 'Swap parameter previous' })
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: all textobject checks `ok`, `0 failure(s)`.

Note on `]c`: gitsigns does not bind `]c` in this config (it uses `]h`/`[h`, see
`lua/plugins/git.lua`), so there is no collision. Neovim's built-in `]c` is a
diff-mode motion, only active in a diff buffer.

- [ ] **Step 5: Verify the textobjects work on a real buffer**

Static assertions cannot prove the queries resolve. Write `/tmp/to_probe.lua`:

```lua
-- Selects a whole Python function with `vam` and reports the selected range.
local f = vim.fn.tempname() .. '.py'
vim.fn.writefile({
  'def outer():',
  '    x = 1',
  '    return x',
  '',
  'def other():',
  '    pass',
}, f)
vim.cmd.edit(f)
vim.bo.filetype = 'python'
vim.wait(5000, function() return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil end, 100)

vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- inside `outer`
vim.cmd 'normal vam'
local s, e = vim.fn.line "'<", vim.fn.line "'>"
print(('selected lines %d-%d (expect 1-3)'):format(s, e))

-- ]m must reach the second function, not be shadowed by ftplugin/python.vim.
vim.cmd 'normal! \27'
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd 'normal ]m'
print((']m landed on line %d (expect 5)'):format(vim.fn.line '.'))
os.exit((s == 1 and e == 3 and vim.fn.line '.' == 5) and 0 or 1)
```

Run it:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -u "$HOME/.config/nvim-dev/init.lua" -l /tmp/to_probe.lua
```

Expected: `selected lines 1-3 (expect 1-3)` and `]m landed on line 5 (expect 5)`,
exit 0. If `]m` lands on line 1, `vim.g.no_python_maps` is not taking effect.

Then clean up: `rm /tmp/to_probe.lua`

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/treesitter.lua tests/health.lua
git commit -m "feat(treesitter): add function/class textobjects and movements"
```

---

## Task 5: lazydev.nvim — Lua API completion for this config

Relevant because this repo is a 2000-line Neovim config. Gated to `FileType lua`,
so it costs nothing when editing anything else.

**Files:**
- Modify: `lua/plugins/lsp.lua`
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertion**

Append to the `== editor QoL ==` section in `tests/health.lua`:

```lua
-- lazydev: on-demand vim.* types when editing this config. Gated to
-- FileType lua, so it is NOT loaded in a headless run with no Lua buffer --
-- assert the source wires it rather than that it is loaded.
local lsp_src2 = io.open(vim.fn.stdpath 'config' .. '/lua/plugins/lsp.lua', 'r')
if lsp_src2 then
  local src2 = lsp_src2:read 'a'
  lsp_src2:close()
  check('lazydev registered', src2:match 'lazydev' ~= nil)
  check('lazydev gated to lua filetype', src2:match "pattern = 'lua'" ~= nil, 'must not load for every filetype')
end
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: `FAIL lazydev registered` and `FAIL lazydev gated to lua filetype`.

- [ ] **Step 3: Add lazydev**

In `lua/plugins/lsp.lua`, insert immediately before the final enablement loop
(the `for name, cfg in pairs(servers) do` block at the end of the file):

```lua
-- lazydev.nvim: on-demand Neovim API types for Lua.
--
-- Worth having specifically because this repo IS a Neovim config. The lua_ls
-- on_init above already registers workspace libraries; lazydev is complementary
-- -- it resolves types per `require` as you type, rather than scanning the whole
-- runtime up front.
--
-- DEFERRED to the first Lua buffer. Not `load = false`: as documented in
-- lua/plugins/completion.lua, that still lands the plugin on runtimepath and
-- lets Neovim source its plugin/ files during the same startup.
--
-- Ordering is not a concern. lazydev pushes workspace/didChangeConfiguration to
-- clients that are already running (its lsp.lua:92), so it works whether it
-- loads before or after lua_ls starts.
local lazydev_ready = false

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Load lazydev on the first Lua buffer',
  group = vim.api.nvim_create_augroup('config-lazydev', { clear = true }),
  pattern = 'lua',
  callback = function()
    if lazydev_ready then return end
    lazydev_ready = true

    vim.pack.add { gh 'folke/lazydev.nvim' }
    require('lazydev').setup {
      library = {
        -- Types for vim.uv, which is a C module lua_ls cannot introspect.
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    }
  end,
})
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: both `lazydev` checks `ok`, `0 failure(s)`.

- [ ] **Step 5: Verify it loads on a Lua buffer and not otherwise**

Write `/tmp/lazydev_probe.lua`:

```lua
-- lazydev must stay unloaded for a non-Lua buffer and load for a Lua one.
local py = vim.fn.tempname() .. '.py'
vim.fn.writefile({ 'x = 1' }, py)
vim.cmd.edit(py)
print('after python buffer, lazydev loaded: ' .. tostring(package.loaded.lazydev ~= nil) .. ' (expect false)')

local lua_file = vim.fn.tempname() .. '.lua'
vim.fn.writefile({ 'local x = vim.uv' }, lua_file)
vim.cmd.edit(lua_file)
vim.wait(5000, function() return package.loaded.lazydev ~= nil end, 100)
print('after lua buffer, lazydev loaded: ' .. tostring(package.loaded.lazydev ~= nil) .. ' (expect true)')
```

Run it:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -u "$HOME/.config/nvim-dev/init.lua" -l /tmp/lazydev_probe.lua
```

Expected: `false` after the Python buffer, `true` after the Lua buffer.

Then clean up: `rm /tmp/lazydev_probe.lua`

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/lsp.lua tests/health.lua
git commit -m "feat(lsp): add lazydev for Lua config editing"
```

---

## Task 6: persistence.nvim — session management

Nothing currently saves buffer or window layout. Keymaps match LazyVim's
`<leader>q*`.

**Files:**
- Modify: `lua/plugins/editor.lua`
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertions**

Append to the `== editor QoL ==` section in `tests/health.lua`:

```lua
-- Sessions. Deferred to the first <leader>q press, so assert the keymaps exist
-- rather than that the plugin is loaded.
for _, lhs in ipairs { '<leader>qs', '<leader>qS', '<leader>ql', '<leader>qd' } do
  check('session keymap ' .. lhs, has_nmap(lhs))
end
check('persistence NOT loaded at startup', package.loaded.persistence == nil, 'must stay deferred')
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: all four `session keymap` checks fail. The
`persistence NOT loaded` check passes trivially at this point — that is expected;
it is a guard against a future regression, not a driver for this task.

- [ ] **Step 3: Add persistence**

Append to `lua/plugins/editor.lua`:

```lua
-- persistence.nvim: session management.
--
-- Chosen over mini.sessions (which is already on disk) because it matches
-- LazyVim's <leader>q* keymaps, preserving the muscle memory this config mirrors
-- everywhere else, and because it autosaves on VimLeavePre rather than needing a
-- manual save.
--
-- DEFERRED to the first <leader>q press, for the reason in
-- lua/plugins/completion.lua.
--
-- KNOWN TRADE-OFF: persistence.setup() calls start() internally, which is what
-- registers the VimLeavePre autosave. Because setup runs lazily, a session is
-- only written if you touched a session keymap during that Neovim run. Making
-- autosave unconditional would mean loading it eagerly; that is the cost this
-- config is not willing to pay for a feature used at session boundaries.
local persistence_specs = { gh 'folke/persistence.nvim' }
local persistence_ready = false

local function setup_persistence()
  if persistence_ready then return end
  persistence_ready = true

  vim.pack.add(persistence_specs)
  require('persistence').setup {}
end

---Wraps a persistence action so the first invocation loads the plugin.
---@param fn fun(p: table)
---@return fun()
local function lazy_session(fn)
  return function()
    setup_persistence()
    fn(require 'persistence')
  end
end

vim.keymap.set('n', '<leader>qs', lazy_session(function(p) p.load() end), { desc = 'Restore session' })
vim.keymap.set('n', '<leader>qS', lazy_session(function(p) p.select() end), { desc = 'Select session' })
vim.keymap.set('n', '<leader>ql', lazy_session(function(p) p.load { last = true } end), { desc = 'Restore last session' })
vim.keymap.set('n', '<leader>qd', lazy_session(function(p) p.stop() end), { desc = "Don't save current session" })
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: all four `session keymap` checks `ok`, `persistence NOT loaded at
startup` still `ok`, `0 failure(s)`.

- [ ] **Step 5: Register the which-key group**

`<leader>q` has no group label yet. In `lua/plugins/ui.lua`, in the `which-key`
`spec` table, add after the `{ '<leader>g', group = 'Git' }` line:

```lua
        { '<leader>q', group = 'Session/Quit' },
```

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/editor.lua lua/plugins/ui.lua tests/health.lua
git commit -m "feat(editor): add persistence.nvim session management"
```

---

## Task 7: grug-far.nvim — project-wide search and replace

Telescope greps but cannot replace across files.

**Files:**
- Modify: `lua/plugins/editor.lua`
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertion**

Append to the `== editor QoL ==` section in `tests/health.lua`:

```lua
-- Project-wide replace. Telescope can grep but not replace across files.
check('search-and-replace keymap <leader>sr', has_nmap '<leader>sr')
check('grug-far NOT loaded at startup', package.loaded['grug-far'] == nil, 'must stay deferred')
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: `FAIL search-and-replace keymap <leader>sr`.

- [ ] **Step 3: Add grug-far**

Append to `lua/plugins/editor.lua`:

```lua
-- grug-far.nvim: project-wide find and replace.
--
-- Telescope covers grep but has no multi-file replace. <leader>sr matches
-- LazyVim. Deferred to first use, as everywhere else in this config.
local grug_specs = { gh 'MagicDuck/grug-far.nvim' }
local grug_ready = false

vim.keymap.set('n', '<leader>sr', function()
  if not grug_ready then
    grug_ready = true
    vim.pack.add(grug_specs)
    require('grug-far').setup { headerMaxWidth = 80 }
  end
  require('grug-far').open()
end, { desc = 'Search and Replace' })
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: both checks `ok`, `0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add lua/plugins/editor.lua tests/health.lua
git commit -m "feat(editor): add grug-far project-wide search and replace"
```

---

## Task 8: Bracket navigation keymaps

Zero-cost keymaps filling gaps in the existing `]d`/`]e`/`]h` set.

**Files:**
- Modify: `lua/config/keymaps.lua`
- Test: `tests/health.lua`

- [ ] **Step 1: Write the failing assertions**

Append to the `== editor QoL ==` section in `tests/health.lua`:

```lua
-- Bracket navigation, filling the gaps in the existing ]d / ]e / ]h set.
for _, lhs in ipairs { ']t', '[t', ']q', '[q', ']b', '[b' } do
  check('bracket keymap ' .. lhs, has_nmap(lhs))
end
```

- [ ] **Step 2: Run the suite to verify it fails**

```bash
tests/run.sh health
```

Expected: all six `bracket keymap` checks fail.

- [ ] **Step 3: Add the keymaps**

Append to `lua/config/keymaps.lua`:

```lua
-- Bracket navigation, completing the ]d / ]e / ]h set defined elsewhere
-- (diagnostics in lua/config/diagnostics.lua, git hunks in lua/plugins/git.lua).

-- Todo comments. todo-comments is deferred behind the first real buffer
-- (lua/plugins/ui.lua), so load it before jumping; both functions are exported
-- from its init.lua.
map('n', ']t', function()
  pcall(vim.cmd.packadd, 'todo-comments.nvim')
  require('todo-comments').jump_next()
end, { desc = 'Next todo comment' })
map('n', '[t', function()
  pcall(vim.cmd.packadd, 'todo-comments.nvim')
  require('todo-comments').jump_prev()
end, { desc = 'Previous todo comment' })

-- Quickfix. pcall so the end of the list reports instead of throwing E553.
map('n', ']q', function()
  local ok, err = pcall(vim.cmd.cnext)
  if not ok then vim.notify(tostring(err):match '[^\n]*$' or 'No more quickfix items', vim.log.levels.WARN) end
end, { desc = 'Next quickfix item' })
map('n', '[q', function()
  local ok, err = pcall(vim.cmd.cprevious)
  if not ok then vim.notify(tostring(err):match '[^\n]*$' or 'No previous quickfix items', vim.log.levels.WARN) end
end, { desc = 'Previous quickfix item' })

-- Buffers, complementing <S-h> / <S-l> above.
map('n', ']b', '<cmd>bnext<CR>', { desc = 'Next buffer' })
map('n', '[b', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
tests/run.sh health
```

Expected: all six checks `ok`, `0 failure(s)`.

- [ ] **Step 5: Verify `]t` actually jumps**

Write `/tmp/todo_probe.lua`:

```lua
-- ]t must load the deferred todo-comments plugin and jump to the TODO.
local f = vim.fn.tempname() .. '.lua'
vim.fn.writefile({ 'local a = 1', '-- TODO: fix this', 'local b = 2' }, f)
vim.cmd.edit(f)
vim.cmd 'doautocmd BufReadPost'
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd 'normal ]t'
print((']t landed on line %d (expect 2)'):format(vim.fn.line '.'))
os.exit(vim.fn.line '.' == 2 and 0 or 1)
```

Run it:

```bash
NVIM_APPNAME=nvim-dev nvim --headless -u "$HOME/.config/nvim-dev/init.lua" -l /tmp/todo_probe.lua
```

Expected: `]t landed on line 2 (expect 2)`, exit 0.

Then clean up: `rm /tmp/todo_probe.lua`

- [ ] **Step 6: Commit**

```bash
git add lua/config/keymaps.lua tests/health.lua
git commit -m "feat(keymaps): add ]t, ]q and ]b bracket navigation"
```

---

## Task 9: Remove stale plugin directories

Five directories from the pre-telescope migration are on disk but absent from
the config. Harmless (not on runtimepath unless added) but worth removing.

**Files:**
- No source changes. Runtime state only.

- [ ] **Step 1: Confirm each is genuinely unreferenced**

```bash
for p in fzf-lua oil.nvim tokyonight.nvim guess-indent.nvim; do
  printf '%s: ' "$p"
  grep -rq "${p%%.nvim}" --include='*.lua' lua/ init.lua && echo REFERENCED || echo unreferenced
done
```

Expected: all four report `unreferenced`. If any reports `REFERENCED`, leave that
one alone and note it.

Note `FixCursorHold.nvim` is deliberately NOT in this list: it is a declared
neotest dependency at `lua/plugins/test.lua:15`. It is obsolete for Neovim 0.12,
but removing a working test dependency is out of scope.

- [ ] **Step 2: Remove them**

```bash
NVIM_APPNAME=nvim-dev nvim --headless -u "$HOME/.config/nvim-dev/init.lua" \
  -c "lua vim.pack.del { 'fzf-lua', 'oil.nvim', 'tokyonight.nvim', 'guess-indent.nvim' }" -c q
```

If `vim.pack.del` errors for a name it does not manage, remove that name from the
list and re-run.

- [ ] **Step 3: Verify the suite still passes**

```bash
tests/run.sh
```

Expected: all three suites PASS. This is the check that none of the removed
directories was silently in use.

- [ ] **Step 4: Commit the refreshed lock file**

`vim.pack.del` rewrites `nvim-pack-lock.json`.

```bash
git add nvim-pack-lock.json
git commit -m "chore: remove stale plugin directories from pre-telescope migration"
```

---

## Task 10: Update `:checkhealth config` and README

**Files:**
- Modify: `lua/config/health.lua`
- Modify: `README.md`

- [ ] **Step 1: Add a health check for the indent-guide owner**

In `lua/config/health.lua`, add this function after `check_single_lsp_owner()`:

```lua
--- INVARIANT 4: exactly one plugin draws indent guides. mini.indentscope and
--- snacks.indent both write extmarks to the same columns; running both flickers.
local function check_single_indent_owner()
  local snacks_indent = package.loaded.snacks and Snacks.config.indent and Snacks.config.indent.enabled
  if snacks_indent and package.loaded['mini.indentscope'] then
    vim.health.error 'mini.indentscope AND snacks.indent both active -- overlapping extmarks will flicker'
  elseif snacks_indent then
    vim.health.ok 'indent guides: snacks.indent'
  else
    vim.health.ok 'indent guides: mini.indentscope (single owner)'
  end
end
```

Then call it from `M.check()`. Find the `vim.health.start` section that runs
`check_single_lsp_owner()` and add on the following line:

```lua
  check_single_indent_owner()
```

- [ ] **Step 2: Verify checkhealth runs clean**

```bash
NVIM_APPNAME=nvim-dev nvim --headless -u "$HOME/.config/nvim-dev/init.lua" \
  -c 'checkhealth config' -c 'w! /tmp/health.txt' -c 'qa!' && grep -E 'ERROR|WARNING|indent' /tmp/health.txt
```

Expected: an `indent guides: mini.indentscope (single owner)` line and no new
ERROR lines. Missing optional external tools may still appear as warnings; those
are pre-existing.

Then clean up: `rm /tmp/health.txt`

- [ ] **Step 3: Update the README keymap table**

In `README.md`, in the keymap table, add these rows after the
`| `<leader>uh` | toggle inlay hints (on by default in Rust only) |` row:

```markdown
| `<leader>n` / `<leader>un` | notification history / dismiss |
| `<leader>sr` | project-wide search and replace (grug-far) |
| `<leader>qs` / `qS` / `ql` / `qd` | restore / select / restore-last / stop session |
| `am` / `im`, `ac` / `ic` | function / class textobject (treesitter) |
| `]m` / `[m`, `]c` / `[c` | next / prev function, next / prev class |
| `]a` / `[a` | swap parameter forward / back |
| `]t` / `[t` | next / previous todo comment |
| `]q` / `[q` | next / previous quickfix item |
| `]b` / `[b` | next / previous buffer |
```

- [ ] **Step 4: Update the README plugin set**

In `README.md`, find the "Plugin set" paragraph ending
`rustaceanvim, nvim-dap, neotest.` and replace that sentence with:

```markdown
rustaceanvim, nvim-dap, neotest. QoL layer: snacks.nvim (bigfile guard, fast
first render, notifications, input), mini.pairs, mini.indentscope,
nvim-treesitter-textobjects, lazydev, persistence and grug-far.
```

- [ ] **Step 5: Note the textobject key-scheme departure**

In `README.md`, the "Two deliberate departures from LazyVim" list needs a third
entry. Change the heading to `Three deliberate departures from LazyVim` and add:

```markdown
* **Textobjects use `am`/`im` and `ac`/`ic`**, the treesitter-textobjects
  upstream scheme, rather than LazyVim's `af`/`if`. `f` is already mini.ai's
  function-*call* textobject, so the upstream keys keep both without a remap.
```

- [ ] **Step 6: Run markdownlint**

```bash
~/.local/share/nvim/mason/bin/markdownlint-cli2 README.md
```

Expected: no errors. If the binary is missing, skip — it is not enforced by
`tests/run.sh`.

- [ ] **Step 7: Commit**

```bash
git add lua/config/health.lua README.md
git commit -m "docs: document QoL additions and add indent-owner health check"
```

---

## Task 11: Final verification

- [ ] **Step 1: Run the full suite**

```bash
tests/run.sh
```

Expected: `health PASSED`, `startup PASSED`, `gd PASSED`.

- [ ] **Step 2: Confirm the startup budget**

From the startup output, record the median. Expected ~100-105 ms against the
125 ms budget. If it exceeds 125 ms, the startup suite fails — report the number
rather than raising the budget.

- [ ] **Step 3: Confirm the deferral invariants held**

```bash
tests/run.sh health 2>&1 | grep -E 'NOT loaded|deferred'
```

Expected: every `deferred` and `NOT loaded` check reports `ok` — blink.cmp,
luasnip, dap, neotest, mason, persistence and grug-far all still off the startup
path.

- [ ] **Step 4: Interactive smoke test**

Automated checks cannot see rendering. Open Neovim normally and confirm:

```bash
NVIM_APPNAME=nvim-dev nvim lua/plugins/editor.lua
```

- indent guides draw on the current scope
- typing `(` inserts `()`
- pressing Enter between `{` and `}` lands on an indented blank line
- `:lua vim.notify('hello')` shows a popup, not a `:messages` line
- `vam` selects a whole function
- `<leader>sr` opens the grug-far window

- [ ] **Step 5: Report**

Summarise: final startup median vs budget, suites passing, and anything that
behaved differently from the plan.

---

## Self-review

**Spec coverage** — every numbered spec section maps to a task: §1 snacks → Task 1;
§2 mini.indentscope → Task 3; §3 mini.pairs → Task 2; §4 textobjects → Task 4;
§5 lazydev → Task 5; §6 persistence → Task 6; §7 grug-far → Task 7; §8 bracket
keymaps → Task 8; §9 cleanup → Task 9. Spec's "File layout" table also lists
`lua/config/health.lua` and `README.md` → Task 10. All five spec testing
invariants are asserted: `<CR>` ownership (Task 2 Step 5), single indent owner
(Task 1 + Task 10), `no_python_maps` (Task 4), snacks module scope (Task 1),
startup budget (Tasks 1, 3, 11).

**Placeholder scan** — no TBDs. Every code step shows complete code; every command
has expected output.

**Consistency** — `gh` helper used throughout (defined in `init.lua`). `has_nmap`
and `loads` and `check` are existing `tests/health.lua` helpers. Deferral flags
are uniquely named per file (`persistence_ready`, `grug_ready`, `lazydev_ready`,
`tree_ready`, `trouble_ready`). Task 3 Step 3 explicitly corrects the assertion
string from Step 1 (`miniindentscope_disable`, not `MiniIndentscopeDisable`) so
the two match.

**One risk flagged for the implementer:** Task 4's `]c`/`[c` are also Vim's
built-in diff-mode motions. They are only active in a diff buffer, and gitsigns
here uses `]h`/`[h`, so there is no conflict in normal editing — but inside
`:diffthis` the treesitter mapping will win. If that proves annoying, drop
`]c`/`[c` and keep `]m`/`[m` only.
