return {
  -- {
  --   "sudo-tee/opencode.nvim",
  --   config = function()
  --     require("opencode").setup({})
  --   end,
  --   dependencies = {
  --     "nvim-lua/plenary.nvim",
  --     {
  --       "MeanderingProgrammer/render-markdown.nvim",
  --       opts = {
  --         anti_conceal = { enabled = false },
  --         file_types = { "markdown", "opencode_output" },
  --       },
  --       ft = { "markdown", "Avante", "copilot-chat", "opencode_output" },
  --     },
  --   },
  -- },
  {
    "Nkr1shna/truffle.nvim",
    config = function()
      require("truffle").setup({
        profiles = {
          cursor = {
            command = "cursor-agent",
            mappings = {
              toggle = "<leader>at",
              send_selection = "<leader>as",
              send_file = "<leader>af",
              send_input = "<leader>ai",
            },
          },
        },
      })
    end,
  },
  {
    "NickvanDyke/opencode.nvim",
    dependencies = { "folke/snacks.nvim" },
    ---@type opencode.Config
    opts = {
      -- Your configuration, if any
    },
    -- stylua: ignore
    keys = {
      { '<leader>ot', function() require('opencode').toggle() end, desc = 'Toggle embedded opencode', },
      { '<leader>oa', function() require('opencode').ask('@cursor: ') end, desc = 'Ask opencode', mode = 'n', },
      { '<leader>oa', function() require('opencode').ask('@selection: ') end, desc = 'Ask opencode about selection', mode = 'v', },
      { '<leader>op', function() require('opencode').select_prompt() end, desc = 'Select prompt', mode = { 'n', 'v', }, },
      { '<leader>on', function() require('opencode').command('session_new') end, desc = 'New session', },
      { '<leader>oy', function() require('opencode').command('messages_copy') end, desc = 'Copy last message', },
      { '<S-C-u>',    function() require('opencode').command('messages_half_page_up') end, desc = 'Scroll messages up', },
      { '<S-C-d>',    function() require('opencode').command('messages_half_page_down') end, desc = 'Scroll messages down', },
    },
  },
  -- {
  --   "jonroosevelt/gemini-cli.nvim",
  --   config = function()
  --     require("gemini").setup()
  --   end,
  -- },
  -- {
  --   "GeorgesAlkhouri/nvim-aider",
  --   cmd = "Aider",
  --   keys = {
  --     { "<leader>a/", "<cmd>Aider toggle<cr>", desc = "Toggle Aider" },
  --     { "<leader>as", "<cmd>Aider send<cr>", desc = "Send to Aider", mode = { "n", "v" } },
  --     { "<leader>ac", "<cmd>Aider command<cr>", desc = "Aider Commands" },
  --     { "<leader>ab", "<cmd>Aider buffer<cr>", desc = "Send Buffer" },
  --     { "<leader>a+", "<cmd>Aider add<cr>", desc = "Add File" },
  --     { "<leader>a-", "<cmd>Aider drop<cr>", desc = "Drop File" },
  --     { "<leader>ar", "<cmd>Aider add readonly<cr>", desc = "Add Read-Only" },
  --     { "<leader>aR", "<cmd>Aider reset<cr>", desc = "Reset Session" },
  --   },
  --   dependencies = {
  --     "folke/snacks.nvim",
  --     --- The below dependencies are optional
  --     "catppuccin/nvim",
  --   },
  --   config = true,
  -- },
}
