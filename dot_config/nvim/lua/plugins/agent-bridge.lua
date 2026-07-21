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
        min_height = 8,
        max_height = 18,
        title = " Compose to Agent ",
      },
    },
    keys = {
      {
        "<leader>oa",
        function()
          require("agent_bridge").context.compose("file")
        end,
        desc = "Compose to agent",
      },
      {
        "<leader>oa",
        function()
          require("agent_bridge").context.compose_visual()
        end,
        mode = "x",
        desc = "Compose to agent",
      },
      {
        "<leader>oA",
        function()
          require("agent_bridge").context.send("file")
        end,
        desc = "Add context to agent",
      },
      {
        "<leader>oA",
        function()
          require("agent_bridge").context.send_visual()
        end,
        mode = "x",
        desc = "Add context to agent",
      },
      {
        "<leader>or",
        function()
          require("agent_bridge").prompt.resume()
        end,
        desc = "Resume agent prompt",
      },
      {
        "<leader>ot",
        function()
          require("agent_bridge").target.select()
        end,
        desc = "Pin agent target",
      },
      {
        "<leader>oT",
        function()
          require("agent_bridge").target.clear()
        end,
        desc = "Clear pinned agent target",
      },
    },
  },
}
