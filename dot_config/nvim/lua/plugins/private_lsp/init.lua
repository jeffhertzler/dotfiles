local M = {}

local handlers =  {
  ["textDocument/hover"] =  vim.lsp.with(vim.lsp.handlers.hover, { border = 'rounded' }),
  ["textDocument/signatureHelp"] =  vim.lsp.with(vim.lsp.handlers.signature_help, { border = 'rounded' }),
}

local on_attach = function(client)
  if client.resolved_capabilities.code_lens then
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
  sumneko_lua = vim.tbl_extend('force', require('lua-dev').setup({
    library = { plugins = false } -- TODO: too slow with all plugins, consider narrowing to allowlist
  }), {

  }),
  tsserver = {
    on_attach = function(client)
      local ts_utils = require("nvim-lsp-ts-utils")
      client.resolved_capabilities.document_formatting = false

      ts_utils.setup({
        enable_import_on_completion = true,
        auto_inlay_hints = false,
      })

      on_attach(client)

      ts_utils.setup_client(client)
    end
  }
}

function M.config()
  local null_ls = require("null-ls")
  null_ls.setup({
    sources = {
      null_ls.builtins.diagnostics.eslint.with({
        condition = function(utils)
          return utils.root_has_file({ '.eslintrc.*' })
        end,
      }),
      null_ls.builtins.code_actions.eslint.with({
        condition = function(utils)
          return utils.root_has_file({ '.eslintrc.*' })
        end,
      }),
      null_ls.builtins.formatting.prettier,
    }
  })
  require("nvim-lsp-installer").on_server_ready(function(server)
    local opts = M.configs[server.name] or {}
    opts.handlers = handlers
    opts.capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
    if (not opts.on_attach) then opts.on_attach = on_attach end

    server:setup(opts);
  end)
end

return M


