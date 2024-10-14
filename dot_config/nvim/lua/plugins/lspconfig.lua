return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      vtsls = {
        settings = {
          vtsls = {
            experimental = {
              maxInlayHintLength = 20,
            },
          },
        },
      },
    },
  },
}
