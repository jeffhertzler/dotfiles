return {
  {
    "folke/sidekick.nvim",
    opts = {
      nes = { enabled = false },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        copilot = { enabled = false },
      },
    },
  },
}
