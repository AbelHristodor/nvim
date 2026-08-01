-- harpoon (branch harpoon2): pin the handful of files you ping-pong between.
--
-- Complements telescope rather than duplicating it: telescope SEARCHES the
-- checkout, harpoon holds an ordered, manually-curated shortlist that survives
-- across sessions (its list is persisted per project root under stdpath('data')).
--
-- BRANCH SPEC, not the `gh` shorthand. harpoon2 lives on a non-default branch,
-- so it needs the table form of a vim.pack spec (src + version); `gh` only
-- returns the URL string that the default-branch plugins use.
--
-- DEFERRED to first use, like every other non-startup plugin here (see the note
-- in lua/plugins/completion.lua on why `load = false` is not enough): the specs
-- are only handed to vim.pack.add on the first <leader>h press, and setup runs
-- once behind a ready flag.
local harpoon_specs = {
  { src = gh 'ThePrimeagen/harpoon', version = 'harpoon2' },
  gh 'nvim-lua/plenary.nvim', -- already on disk via git.lua; listed for correctness
}
local harpoon_ready = false

---Loads harpoon on first use and returns the module.
---@return table
local function get_harpoon()
  if not harpoon_ready then
    harpoon_ready = true
    vim.pack.add(harpoon_specs)
    require('harpoon'):setup {}
  end
  return require 'harpoon'
end

-- Telescope UI for the harpoon list. harpoon2 has no built-in picker beyond its
-- own toggle_quick_menu window; this renders the list through telescope so it
-- matches the finder used everywhere else in this config, and adds a mapping to
-- delete an entry from the list without leaving the picker.
---@param harpoon table
local function toggle_telescope(harpoon)
  local list = harpoon:list()

  local file_paths = {}
  for _, item in ipairs(list.items) do
    table.insert(file_paths, item.value)
  end

  local conf = require('telescope.config').values
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Harpoon',
      finder = require('telescope.finders').new_table { results = file_paths },
      previewer = conf.file_previewer {},
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        map('i', '<C-d>', function()
          local state = require 'telescope.actions.state'
          local selection = state.get_selected_entry()
          if selection then
            list:remove_at(selection.index)
            -- Reopen so the picker reflects the shorter list.
            require('telescope.actions').close(prompt_bufnr)
            toggle_telescope(harpoon)
          end
        end)
        return true
      end,
    })
    :find()
end

local map = vim.keymap.set

-- Add / list. <leader>h prefix (which-key group registered in plugins/ui.lua).
map('n', '<leader>ha', function()
  local h = get_harpoon()
  h:list():add()
end, { desc = 'Harpoon add file' })

map('n', '<leader>hh', function()
  local h = get_harpoon()
  toggle_telescope(h)
end, { desc = 'Harpoon menu (telescope)' })

map('n', '<leader>hm', function()
  local h = get_harpoon()
  h.ui:toggle_quick_menu(h:list())
end, { desc = 'Harpoon quick menu' })

-- Cycle through the list.
map('n', '<leader>hn', function() get_harpoon():list():next() end, { desc = 'Harpoon next' })
map('n', '<leader>hp', function() get_harpoon():list():prev() end, { desc = 'Harpoon prev' })

-- Jump straight to a slot. <C-hjkl> are window motions (lua/config/keymaps.lua)
-- and ]h / [h are gitsigns hunk-nav, so the numbered slots live under <leader>h.
for i = 1, 5 do
  map('n', '<leader>h' .. i, function() get_harpoon():list():select(i) end, { desc = 'Harpoon to file ' .. i })
end
