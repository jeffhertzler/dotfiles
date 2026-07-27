if vim.fn.executable("go") == 1 then
  return {}
end

local go_tools = {
  delve = true,
  gofumpt = true,
  goimports = true,
  ["golangci-lint"] = true,
  gomodifytags = true,
  impl = true,
}

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.gopls = vim.tbl_deep_extend("force", opts.servers.gopls or {}, {
        enabled = false,
        mason = false,
      })
    end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = vim.tbl_filter(function(tool)
        return not go_tools[tool]
      end, opts.ensure_installed or {})
    end,
  },
}
