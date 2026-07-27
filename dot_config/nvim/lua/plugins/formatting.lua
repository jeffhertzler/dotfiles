return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      if vim.fn.has("win32") ~= 1 then
        return
      end

      -- vim.system() cannot safely launch an absolute .cmd path containing
      -- spaces. Run Mason's Oxfmt JavaScript entry point through Node instead.
      local oxfmt_cli = vim.fs.joinpath(
        vim.fn.stdpath("data"),
        "mason",
        "packages",
        "oxfmt",
        "node_modules",
        "oxfmt",
        "dist",
        "cli.js"
      )

      opts.formatters = opts.formatters or {}
      opts.formatters.oxfmt = vim.tbl_deep_extend("force", opts.formatters.oxfmt or {}, {
        command = vim.fn.exepath("node"),
        prepend_args = { oxfmt_cli },
      })
    end,
  },
}
