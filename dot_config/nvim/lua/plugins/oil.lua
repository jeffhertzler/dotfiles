return {
  "stevearc/oil.nvim",
  dependencies = { { "echasnovski/mini.icons", opts = {} } },
  lazy = false,
  keys = {
    {
      "-",
      "<cmd>Oil<cr>",
      desc = "Open parent directory",
    },
  },
  config = function()
    local oil = require("oil")
    oil.setup({
      keymaps = {
        ["<C-h>"] = false,
        ["<C-l>"] = false,
        ["<C-t>"] = false,
        ["RR"] = "actions.refresh",
        ["<C-A-j>"] = "actions.select_split",
        ["<C-A-l>"] = "actions.select_vsplit",
      },
      lsp_file_methods = {
        autosave_changes = "unmodified",
      },
      skip_confirm_for_simple_edits = true,
      -- experimental_watch_for_changes = true,
      view_options = {
        show_hidden = true,
      },
    })
  end,
}
