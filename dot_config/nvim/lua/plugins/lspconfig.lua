local util = require("lspconfig.util")

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
        workspace_required = true,
        root_dir = function(bufnr, on_dir)
          local fname = vim.api.nvim_buf_get_name(bufnr)
          local root = util.root_pattern("ember-cli-build.js")(fname)

          if root then
            on_dir(root)
          end
        end,
      },
      eslint = {
        root_dir = function(bufnr, on_dir)
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
      oxfmt = {
        enabled = true,
        root_dir = function(bufnr, on_dir)
          local fname = vim.api.nvim_buf_get_name(bufnr)
          local root_markers =
            util.insert_package_json({ ".oxfmtrc.json", ".oxfmtrc.jsonc", "oxfmt.config.ts" }, "oxfmt", fname)
          local root_file = vim.fs.find(root_markers, { path = fname, upward = true })[1]

          if root_file then
            on_dir(vim.fs.dirname(root_file))
          end
        end,
      },
      graphql = {
        filetypes = { "graphql", "typescriptreact", "javascriptreact", "typescript", "javascript" },
      },
      tailwindcss = {
        root_dir = function(bufnr, on_dir)
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
