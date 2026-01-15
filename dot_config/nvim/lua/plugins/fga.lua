return {
  "hedengran/fga.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("fga").setup({
      lsp_server = "/home/jeffhertzler/dev/vscode-ext/server/out/server.node.js",
    })
  end,
}
