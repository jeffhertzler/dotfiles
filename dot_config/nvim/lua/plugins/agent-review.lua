return {
  {
    dir = vim.fn.stdpath("config") .. "/local/agent-review.nvim",
    name = "agent-review.nvim",
    main = "agent_review",
    lazy = false,
    opts = {},
    keys = {
      {
        "<leader>ra",
        function()
          require("agent_review").annotation.add()
        end,
        desc = "Add review annotation",
      },
      {
        "<leader>ra",
        function()
          require("agent_review").annotation.add({ visual = true })
        end,
        mode = "x",
        desc = "Annotate selection",
      },
      {
        "<leader>rd",
        function()
          require("agent_review").annotation.remove()
        end,
        desc = "Remove review annotation",
      },
      {
        "<leader>re",
        function()
          require("agent_review").annotation.edit()
        end,
        desc = "Edit review annotation",
      },
      {
        "<leader>rl",
        function()
          require("agent_review").ui.annotations()
        end,
        desc = "List review annotations",
      },
      {
        "<leader>rs",
        function()
          require("agent_review").send()
        end,
        desc = "Send review annotations",
      },
    },
  },
}
