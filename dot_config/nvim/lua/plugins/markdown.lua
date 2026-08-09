local markdown_preview_build

if vim.fn.has("win32") == 1 then
  markdown_preview_build = function(plugin)
    local app_dir = vim.fs.joinpath(plugin.dir, "app")
    local package_file = vim.fs.joinpath(plugin.dir, "package.json")
    local package = vim.json.decode(table.concat(vim.fn.readfile(package_file), "\n"))
    local result = vim
      .system({ "cmd.exe", "/d", "/c", "install.cmd", "v" .. package.version }, { cwd = app_dir, text = true })
      :wait()

    if result.code ~= 0 then
      error(result.stderr ~= "" and result.stderr or result.stdout)
    end
  end
end

return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", vim.fs.joinpath(vim.fn.expand("~"), ".markdownlint.json"), "-" },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters = {
        ["markdownlint-cli2"] = {
          args = {
            "--config",
            vim.fs.joinpath(vim.fn.expand("~"), ".markdownlint.json"),
            "--fix",
            "$FILENAME",
          },
        },
      },
    },
  },
  {
    "iamcco/markdown-preview.nvim",
    build = markdown_preview_build,
  },
}
