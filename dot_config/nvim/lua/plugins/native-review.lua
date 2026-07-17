return {
  {
    dir = vim.fn.stdpath("config") .. "/local/native-review.nvim",
    name = "native-review.nvim",
    main = "native_review",
    lazy = false,
    opts = {},
    keys = {
      {
        "<leader>ra",
        function()
          require("native_review").add()
        end,
        desc = "Add review annotation",
      },
      {
        "<leader>ra",
        function()
          require("native_review").add({ visual = true })
        end,
        mode = "x",
        desc = "Annotate selection",
      },
      {
        "<leader>rd",
        function()
          require("native_review").remove()
        end,
        desc = "Remove review annotation",
      },
      {
        "<leader>re",
        function()
          require("native_review").edit()
        end,
        desc = "Edit review annotation",
      },
      {
        "<leader>rl",
        function()
          require("native_review").list()
        end,
        desc = "List review annotations",
      },
      {
        "<leader>rs",
        function()
          require("native_review").send()
        end,
        desc = "Send review annotations",
      },
    },
  },
}
