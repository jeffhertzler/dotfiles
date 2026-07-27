local lsp_server = vim.env.FGA_LSP_SERVER
  or vim.fs.joinpath(vim.fn.expand("~"), "dev", "vscode-ext", "server", "out", "server.node.js")

return {
  "hedengran/fga.nvim",
  enabled = vim.fn.filereadable(lsp_server) == 1,
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("fga").setup({
      lsp_server = lsp_server,
    })
  end,
}
