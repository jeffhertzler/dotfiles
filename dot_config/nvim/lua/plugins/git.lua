return {
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {
      diff = {
        layout = "inline",
      },
      explorer = {
        hidden = true,
        initial_focus = "modified",
      },
      keymaps = {
        view = {
          quit = "Q",
          close_on_open_in_prev_tab = true,
        },
      },
    },
    keys = {
      { "<leader>gd", "<cmd>CodeDiff<cr>", desc = "Git Diff (CodeDiff)" },
    },
  },
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "esmuellert/codediff.nvim",
      "folke/snacks.nvim",
    },
    opts = {
      kind = "replace",
      treesitter_diff_highlight = true,
      integrations = {
        codediff = true,
        diffview = false,
        snacks = true,
      },
      diff_viewer = "codediff",
      mappings = {
        status = {
          ["q"] = false,
          ["Q"] = "Close",
          ["!"] = "Command",
        },
        commit_editor = {
          ["q"] = false,
          ["Q"] = "Close",
        },
        rebase_editor = {
          ["q"] = false,
          ["Q"] = "Close",
        },
      },
    },
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit Status" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit Commit" },
    },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyVimKeymaps",
        once = true,
        callback = function()
          -- Lazygit remains available through the Herdr/tmux popup.
          pcall(vim.keymap.del, "n", "<leader>gG")
        end,
      })
    end,
  },
}
