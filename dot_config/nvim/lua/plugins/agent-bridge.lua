return {
  {
    dir = vim.fn.stdpath("config") .. "/local/agent-bridge.nvim",
    name = "agent-bridge.nvim",
    main = "agent_bridge",
    lazy = false,
    opts = {
      tmux = {
        process_name = { "pi", "opencode", "cursor-agent", "claude" },
      },
      targets = {
        remember_target = false,
      },
      prompt = {
        width_ratio = 0.5,
        height_ratio = 0.28,
        title = " Compose to Agent ",
      },
    },
    keys = {
      {
        "<leader>oa",
        function()
          require("agent_bridge").send_file({ interactive_prompt = true })
        end,
        desc = "Compose to agent",
      },
      {
        "<leader>oa",
        function()
          require("agent_bridge").compose_visual()
        end,
        mode = "x",
        desc = "Compose to agent",
      },
      {
        "<leader>oA",
        function()
          require("agent_bridge").send_file({})
        end,
        desc = "Add context to agent",
      },
      {
        "<leader>oA",
        function()
          require("agent_bridge").send_visual()
        end,
        mode = "x",
        desc = "Add context to agent",
      },
      {
        "<leader>or",
        function()
          require("agent_bridge").resume_prompt()
        end,
        desc = "Resume agent prompt",
      },
      {
        "<leader>ot",
        function()
          require("agent_bridge").select_target()
        end,
        desc = "Pin agent target",
      },
      {
        "<leader>oT",
        function()
          require("agent_bridge").clear_target()
        end,
        desc = "Clear pinned agent target",
      },
    },
  },
}
