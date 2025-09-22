return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    local keys = require("lazyvim.plugins.lsp.keymaps").get()
    keys[#keys + 1] = { "<c-k>", false, mode = "i" }

    opts.servers.graphql =
      { filetypes = { "graphql", "typescriptreact", "javascriptreact", "typescript", "javascript" } }
  end,
}
