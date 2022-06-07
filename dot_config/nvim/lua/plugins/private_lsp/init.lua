local M = {}

M.started = false

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })

local on_attach = function(client)
  if client.server_capabilities.code_lens then
    vim.lsp.codelens.refresh()
    vim.cmd([[
      augroup lsp_code_lens_refresh
        autocmd! * <buffer>
        autocmd BufEnter,CursorHold,InsertLeave <buffer> lua vim.lsp.codelens.refresh()
      augroup END
    ]])
  end
end

M.configs = {
  ember = {
    settings = {
      useBuiltinLinting = false,
      addons = {},
    },
  },
  sumneko_lua = vim.tbl_extend(
    "force",
    require("lua-dev").setup({
      library = {
        plugins = false,
      },
    }),
    {}
  ),
  tsserver = {
    on_attach = function(client)
      local ts_utils = require("nvim-lsp-ts-utils")

      ts_utils.setup({
        enable_import_on_completion = true,
        auto_inlay_hints = false,
      })

      on_attach(client)

      ts_utils.setup_client(client)
    end,
  },
}

function M.config()
  if not M.started then
    M.started = true
    local null_ls = require("null-ls")
    null_ls.setup({
      sources = {
        -- null_ls.builtins.formatting.stylua,
        null_ls.builtins.diagnostics.eslint.with({
          condition = function(utils)
            return utils.root_has_file({ ".eslintrc.*" })
          end,
          prefer_local = "node_modules/.bin",
        }),
        null_ls.builtins.code_actions.eslint.with({
          condition = function(utils)
            return utils.root_has_file({ ".eslintrc.*" })
          end,
          prefer_local = "node_modules/.bin",
        }),
        null_ls.builtins.formatting.prettier.with({
          extra_filetypes = { "php" },
          prefer_local = "node_modules/.bin",
        }),
      },
    })
    local lspconfig = require("lspconfig")
    local lspinstaller = require("nvim-lsp-installer")
    local capabilities = require("cmp_nvim_lsp").update_capabilities(vim.lsp.protocol.make_client_capabilities())

    lspinstaller.setup({})

    for _, server in ipairs(lspinstaller.get_installed_servers()) do
      local opts = M.configs[server.name] or {}

      opts.capabilities = capabilities

      if not opts.on_attach then
        opts.on_attach = on_attach
      end

      lspconfig[server.name].setup(opts)
    end
  end
end

function M.format()
  vim.lsp.buf.format({
    filter = function(client)
      return client.name ~= "tsserver" and client.name ~= "ember"
    end,
  })
end

return M
