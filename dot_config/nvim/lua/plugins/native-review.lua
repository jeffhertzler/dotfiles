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
        "<leader>rl",
        function()
          require("native_review").list()
        end,
        desc = "List review annotations",
      },
    },
  },
}
