-- Treesitter: highlighting, indentation and folds.
--
-- Uses the `main` branch, which is the current API (`.install()` /
-- `.get_installed()`) rather than the legacy `master` branch's
-- `configs.setup { ensure_installed = ... }`.

vim.pack.add {
  { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' },
}

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
  -- No 'jsonc': the main branch reports it as an unsupported language and warns
  -- on every startup. Neovim maps the jsonc filetype onto the json parser, so
  -- .jsonc files still highlight correctly.
  'lua',
  'luadoc',
  'luap',
  'markdown',
  'markdown_inline',
  'python',
  'query',
  'regex',
  'rust',
  'toml',
  'tsx',
  'typescript',
  'vim',
  'vimdoc',
  'yaml',
}

local ts = require 'nvim-treesitter'

-- Install missing parsers in the background. Passing the full list on every
-- startup would block, so only ask for what is actually absent.
local installed = ts.get_installed 'parsers'
local missing = vim.tbl_filter(function(lang) return not vim.tbl_contains(installed, lang) end, parsers)
if #missing > 0 then ts.install(missing) end

local available = ts.get_available()

--- Start treesitter for `language` in `buf`, enabling indent when a query exists.
---@param buf integer
---@param language string
local function try_attach(buf, language)
  if not vim.treesitter.language.add(language) then return end
  vim.treesitter.start(buf, language)
  if vim.treesitter.query.get(language, 'indents') ~= nil then vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
end

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Start treesitter, installing the parser on demand',
  group = vim.api.nvim_create_augroup('config-treesitter', { clear = true }),
  callback = function(args)
    local language = vim.treesitter.language.get_lang(args.match)
    if not language then return end

    if vim.tbl_contains(ts.get_installed 'parsers', language) then
      try_attach(args.buf, language)
    elseif vim.tbl_contains(available, language) then
      ts.install(language):await(function() try_attach(args.buf, language) end)
    else
      -- Parser may exist outside nvim-treesitter's registry (e.g. bundled with
      -- Neovim, or installed by hand). pcall because language.add throws for a
      -- genuinely absent parser.
      pcall(try_attach, args.buf, language)
    end
  end,
})

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
