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
  'smithy', -- verified present in nvim-treesitter's registry
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
