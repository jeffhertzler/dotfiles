return {
  "neovim/nvim-lspconfig",
  opts = {
    setup = {
      eslint = function() end,
    },
    servers = {
      ["*"] = {
        keys = {
          { "<c-k>", false },
        },
      },
      eslint = {
        settings = {
          execArgv = { "--max-old-space-size=8192" },
        },
      },
      graphql = {
        filetypes = { "graphql", "typescriptreact", "javascriptreact", "typescript", "javascript" },
      },
      vtsls = {
        tsserver = {
          maxTsServerMemory = 8192,
        },
      },
    },
  },
}
