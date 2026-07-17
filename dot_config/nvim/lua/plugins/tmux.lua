return {
  {
    "alexghergh/nvim-tmux-navigation",
    cond = vim.env.HERDR_ENV ~= "1",
    keys = {
      { "<C-h>", "<cmd>NvimTmuxNavigateLeft<cr>", silent = true },
      { "<C-j>", "<cmd>NvimTmuxNavigateDown<cr>", silent = true },
      { "<C-k>", "<cmd>NvimTmuxNavigateUp<cr>", silent = true },
      { "<C-l>", "<cmd>NvimTmuxNavigateRight<cr>", silent = true },
    },
    opts = {
      disable_when_zoomed = true,
    },
  },
  {
    "lmilojevicc/herdr-splits.nvim",
    cond = vim.env.HERDR_ENV == "1",
    event = "VeryLazy",
    keys = {
      {
        "<C-h>",
        function()
          require("herdr-splits").move_cursor_left()
        end,
        desc = "Navigate left",
      },
      {
        "<C-j>",
        function()
          require("herdr-splits").move_cursor_down()
        end,
        desc = "Navigate down",
      },
      {
        "<C-k>",
        function()
          require("herdr-splits").move_cursor_up()
        end,
        desc = "Navigate up",
      },
      {
        "<C-l>",
        function()
          require("herdr-splits").move_cursor_right()
        end,
        desc = "Navigate right",
      },
      {
        "<M-h>",
        function()
          require("herdr-splits").resize_left()
        end,
        desc = "Resize left",
      },
      {
        "<M-j>",
        function()
          require("herdr-splits").resize_down()
        end,
        desc = "Resize down",
      },
      {
        "<M-k>",
        function()
          require("herdr-splits").resize_up()
        end,
        desc = "Resize up",
      },
      {
        "<M-l>",
        function()
          require("herdr-splits").resize_right()
        end,
        desc = "Resize right",
      },
    },
    opts = {
      at_edge = "stop",
      nav_at_edge = "stop",
      unzoom_on_nav = false,
      auto_sync_herdr = true,
    },
  },
}
