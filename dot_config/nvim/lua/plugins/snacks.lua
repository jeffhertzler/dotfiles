return {
  "folke/snacks.nvim",
  keys = {
    {
      "<leader>gG",
      function()
        Snacks.lazygit({ cwd = LazyVim.root.git() })
      end,
      desc = "Lazygit (Root Dir)",
    },
  },
  opts = {
    picker = {
      matcher = {
        frecency = true,
      },
    },
  },
}
