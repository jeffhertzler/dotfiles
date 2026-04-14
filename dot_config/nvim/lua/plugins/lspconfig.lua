return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      ["*"] = {
        keys = {
          { "<c-k>", false },
        },
      },
      ember = {
        root_dir = function(bufnr, on_dir)
          local util = require("lspconfig.util")
          local fname = vim.api.nvim_buf_get_name(bufnr)
          on_dir(util.root_pattern("ember-cli-build.js")(fname))
        end,
      },
      eslint = {
        root_dir = function(bufnr, on_dir)
          local util = require("lspconfig.util")
          local fname = vim.api.nvim_buf_get_name(bufnr)
          -- If oxlint config is present, disable eslint LSP for this project
          if util.root_pattern(".oxlintrc.json", "oxlint.config.ts")(fname) then
            return
          end
          -- Otherwise use normal eslint root detection
          local root = util.root_pattern(
            ".eslintrc",
            ".eslintrc.js",
            ".eslintrc.cjs",
            ".eslintrc.json",
            "eslint.config.js",
            "eslint.config.mjs",
            "eslint.config.cjs"
          )(fname)

          on_dir(root)
        end,
        settings = {
          execArgv = { "--max-old-space-size=8192" },
        },
      },
      graphql = {
        filetypes = { "graphql", "typescriptreact", "javascriptreact", "typescript", "javascript" },
      },
      tailwindcss = {
        root_dir = function(bufnr, on_dir)
          local util = require("lspconfig.util")
          local fname = vim.api.nvim_buf_get_name(bufnr)
          on_dir(
            util.root_pattern("tailwind.config.js", "tailwind.config.cjs", "tailwind.config.mjs", "tailwind.config.ts")(
              fname
            )
          )
        end,
      },
    },
  },
}
