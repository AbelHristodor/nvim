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
-- NOTE: the plan's fillchars line lost its Nerd Font glyphs for foldopen/
-- foldclose in transit, which Neovim rejects (E1511). Restored with the
-- conventional nf-md chevrons.
o.fillchars = 'fold: ,foldopen:󰅀,foldclose:󰅂,foldsep: '
