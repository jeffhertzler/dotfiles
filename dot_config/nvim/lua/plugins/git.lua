return {
  {
    "esmuellert/codediff.nvim",
    lazy = true,
  },
  {
    dir = vim.fn.stdpath("config") .. "/local/agent-diff.nvim",
    name = "agent-diff.nvim",
    main = "agent_diff",
    lazy = false,
    dependencies = {
      "esmuellert/codediff.nvim",
      "lewis6991/gitsigns.nvim",
    },
    opts = {
      default_revision = "HEAD",
      initial_timeout_ms = 500,
      live_timeout_ms = 100,
    },
    keys = {
      {
        "<leader>gd",
        function()
          require("agent_diff").inline()
        end,
        desc = "Git Diff Inline",
      },
      {
        "<leader>gD",
        function()
          require("agent_diff").side_by_side()
        end,
        desc = "Git Diff Side-by-Side",
      },
      {
        "<leader>gw",
        function()
          require("agent_diff").patch()
        end,
        desc = "Git Patch Workspace",
      },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    opts = function(_, opts)
      local on_attach = opts.on_attach
      opts.on_attach = function(bufnr)
        if on_attach then
          on_attach(bufnr)
        end
        require("agent_diff.gitsigns").setup_buffer(bufnr)
      end
    end,
  },
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim",
      "esmuellert/codediff.nvim",
    },
    opts = {
      kind = "replace",
      treesitter_diff_highlight = true,
      word_diff_highlight = false,
      diff_viewer = "codediff",
      integrations = {
        codediff = true,
        diffview = false,
        snacks = true,
      },
    },
    config = function(_, opts)
      require("neogit").setup(opts)
      require("agent_diff.neogit").setup()
    end,
    keys = {
      {
        "<leader>gg",
        function()
          require("agent_diff.neogit").status()
        end,
        desc = "Neogit Status",
      },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit Commit" },
    },
  },
}
