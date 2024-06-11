return {
  "alexghergh/nvim-tmux-navigation",
  keys = {
    { "<C-h>", "<cmd>NvimTmuxNavigateLeft<cr>", silent = true },
    { "<C-j>", "<cmd>NvimTmuxNavigateDown<cr>", silent = true },
    { "<C-k>", "<cmd>NvimTmuxNavigateUp<cr>", silent = true },
    { "<C-l>", "<cmd>NvimTmuxNavigateRight<cr>", silent = true },
  },
  opts = {
    disable_when_zoomed = true,
  },
}
