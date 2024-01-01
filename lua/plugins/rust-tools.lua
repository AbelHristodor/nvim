return {
  'simrat39/rust-tools.nvim',
  event = {"BufReadPost *.rs"},
  ft = {"rust"},
  opts = {
    server = {
      cmd = { "rust-analyzer" },
      on_attach = function(client, bufnr)
        local rt = require('rust-tools')

        -- Rust specific keymaps
        -- Hover actions
        vim.keymap.set("n", "<C-space>", rt.hover_actions.hover_actions, { buffer = bufnr })
        -- Code action groups
        vim.keymap.set("n", "<Leader>a", require('rust-tools').code_action_group.code_action_group, { buffer = bufnr })
      end,
      settings = {
        ["rust-analyzer"] = {
          checkOnSave = {
            command = "clippy"
          },
        }
      }
    },
    tools = {
      inlay_hints = {
        auto = true,
      },
    }
  }
}
