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
      ember = {
        root_dir = function(fname)
          local util = require("lspconfig.util")
          return util.root_pattern("ember-cli-build.js")(fname)
        end,
      },
      eslint = {
        root_dir = function(fname)
          local util = require("lspconfig.util")
          -- If oxlint config is present, disable eslint LSP for this project
          if util.root_pattern(".oxlintrc.json", "oxlint.config.ts")(fname) then
            return nil
          end
          -- Otherwise use normal eslint root detection
          return util.root_pattern(
            ".eslintrc",
            ".eslintrc.js",
            ".eslintrc.cjs",
            ".eslintrc.json",
            "eslint.config.js",
            "eslint.config.mjs",
            "eslint.config.cjs"
          )(fname)
        end,
        settings = {
          execArgv = { "--max-old-space-size=8192" },
        },
      },
      graphql = {
        filetypes = { "graphql", "typescriptreact", "javascriptreact", "typescript", "javascript" },
      },
      tailwindcss = {
        root_dir = function(fname)
          local util = require("lspconfig.util")
          return util.root_pattern(
            "tailwind.config.js",
            "tailwind.config.cjs",
            "tailwind.config.mjs",
            "tailwind.config.ts"
          )(fname)
        end,
      },
      vtsls = false,
      -- vtsls = {
      --   tsserver = {
      --     maxTsServerMemory = 8192,
      --   },
      -- },
    },
  },
}
