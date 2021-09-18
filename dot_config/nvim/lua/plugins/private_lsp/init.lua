local M = {}

-- local capabilities = vim.lsp.protocol.make_client_capabilities()
-- capabilities.textDocument.completion.completionItem.snippetSupport = true

local loaded = false

M.configs = {
  -- efm = { -- TODO: figure this out or figure out null-ls
  --   filetypes = {
  --     'json',
  --     'javascript',
  --     'javascriptreact',
  --     'javascript.jsx',
  --     'typescript',
  --     'typescript.tsx',
  --     'typescriptreact',
  --   },
  -- },
  ember = {
    settings = {
      useBuiltinLinting = false,
      addons = {},
    },
  },
  lua = vim.tbl_extend('force', require('lua-dev').setup({
    library = { plugins = false } -- TODO: too slow with all plugins, consider narrowing to allowlist
  }), {

  }),
  typescript = {
    on_attach = function(client)
      local ts_utils = require("nvim-lsp-ts-utils")
      client.resolved_capabilities.document_formatting = false

      -- defaults
      ts_utils.setup({
        disable_commands = false,
        debug = false,
        enable_import_on_completion = true,
        import_on_completion_timeout = 5000,

        -- eslint diagnostics
        eslint_disable_if_no_config = true,
        eslint_enable_diagnostics = true,

        -- formatting
        enable_formatting = true,
      })

      -- required to enable ESLint code actions and formatting
      ts_utils.setup_client(client)
    end
  }
}

function M.ember()
  require('lspinstall/servers').ember = {
    install_script = [[
    ! test -f package.json && npm init -y --scope=lspinstall || true
    npm install @lifeart/ember-language-server@latest
    ]],
    default_config = {
      cmd = {'./node_modules/.bin/ember-language-server', '--stdio'},
      filetypes = { 'javascript', 'typescript', 'handlebars', 'html.handlebars' },
      root_dir = require('lspconfig').util.root_pattern('ember-cli-build.js'),
    },
  }
end

function M.start()
  if not loaded then
    M.ember()
    require('null-ls').config({})
    require('lspconfig')['null-ls'].setup({})
    require('lspinstall').setup()
    local servers = require('lspinstall').installed_servers()
    for _, server in pairs(servers) do
      local config = M.configs[server] or {}
      -- config.capabilities = capabilities
      config.capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
      require('lspconfig')[server].setup(config)
      -- require('lspconfig')[server].setup(require("coq")().lsp_ensure_capabilities(config))
    end
    loaded = true
  end
end

function M.restart()
  M.start()
  vim.cmd('bufdo e')
end

function M.config()
  -- require('lspinstall').post_install_hook = M.restart
  M.start()
end

return M


