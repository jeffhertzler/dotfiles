local format = function()
  vim.lsp.buf.format({
    filter = function(c)
      return c.name ~= 'tsserver' and c.name ~= 'ember' and c.name ~= 'copilot'
    end,
  })
end

return {
  'jose-elias-alvarez/null-ls.nvim',
  'jose-elias-alvarez/typescript.nvim',
  {
    'VonHeikemen/lsp-zero.nvim',
    event = "BufReadPre",
    config = function()
      require('neodev').setup()

      local lsp = require('lsp-zero')
      local null_ls = require('null-ls')
      local typescript = require('typescript')
      local utils = require('config.utils')

      lsp.preset('lsp-compe')

      lsp.set_preferences({
        set_lsp_keymaps = false
      })

      local n = utils.make_keymap('n')

      lsp.on_attach(function(client)
        local tb = require('telescope.builtin')

        n('<F2>', function() vim.lsp.buf.rename() end, 'rename')
        n('<F4>', function() vim.lsp.buf.code_action() end, 'code actions')
        n('gd', function() tb.lsp_definitions() end, 'definition')
        n('gD', function() vim.lsp.buf.declaration() end, 'declaration')
        n('gh', function() vim.lsp.buf.hover() end, 'hover')
        n('gH', function() vim.lsp.buf.signature_help() end, 'signature help')
        n('gi', tb.lsp_implementations, 'implementation')
        n('gI', tb.lsp_incoming_calls, 'incoming calls')
        n('gl', function() vim.lsp.buf.open_float() end, 'line diagnostic')
        n('go', tb.lsp_type_definitions, 'type definition')
        n('gO', tb.lsp_outgoing_calls, 'outgoing calls')
        n('gr', tb.lsp_references, 'reference')

        n('<leader>ca', function() vim.lsp.buf.code_action() end, 'actions')

        n('<leader>cdf', function() vim.diagnostic.open_float({ scope = 'c' }) end, 'float (cursor)')
        n('<leader>cdF', function() vim.diagnostic.open_float() end, 'float (line)')
        n('<leader>cdl', function() tb.diagnostics({ bufnr = 0 }) end, 'list')
        n('<leader>cdL', function() tb.diagnostics() end, 'list (workspace)')
        n('<leader>cdn', function() vim.diagnostic.goto_next() end, 'next')
        n('<leader>cdp', function() vim.diagnostic.open_float() end, 'prev')
        n('<leader>cdt', function() require('trouble').toggle({ mode = "document_diagnostics" }) end, 'trouble (buffer)')
        n(
          '<leader>cdT',
          function() require('trouble').toggle({ mode = "workspace_diagnostics" }) end,
          'trouble (workspace)'
        )

        n('<leader>cf', format, 'format')

        n('<leader>cla', function() vim.lsp.codelens.run() end, 'actions')
        n('<leader>clr', function() vim.lsp.codelens.refresh() end, 'refresh')

        if client.name == "tsserver" then
          n('<leader>co', function() require("typescript").actions.organizeImports() end, 'organize (imports)')
        end

        n('<leader>cr', function() vim.lsp.buf.rename() end, 'rename')
        n('<leader>cs', tb.lsp_document_symbols, 'symbols')
        n('<leader>cS', tb.lsp_workspace_symbols, 'symbols (workspace)')
      end)

      lsp.configure('yamlls', {
        settings = {
          yaml = {
            editor = {
              tabSize = 2,
            },
            keyOrdering = false,
          },
        },
      })

      lsp.skip_server_setup({ 'tsserver' })

      lsp.setup()

      local typescript_opts = lsp.build_options('tsserver', {})
      typescript.setup({
        server = typescript_opts,
      })

      local null_opts = lsp.build_options('null-ls', {})

      -- dump(null_opts)
      null_ls.setup({
        --   on_attach = function(client, bufnr)
        --     null_opts.on_attach(client, bufnr)
        --   end,
        sources = {
          -- null_ls.builtins.formatting.stylua,
          require('typescript.extensions.null-ls.code-actions'),
          null_ls.builtins.diagnostics.eslint.with({
            condition = function(nl_utils)
              return nl_utils.root_has_file({
                ".eslintrc",
                ".eslintrc.js",
                ".eslintrc.cjs",
                ".eslintrc.yaml",
                ".eslintrc.yml",
                ".eslintrc.json",
              })
            end,
            prefer_local = "node_modules/.bin",
          }),
          null_ls.builtins.code_actions.eslint.with({
            condition = function(nl_utils)
              return nl_utils.root_has_file({
                ".eslintrc",
                ".eslintrc.js",
                ".eslintrc.cjs",
                ".eslintrc.yaml",
                ".eslintrc.yml",
                ".eslintrc.json",
              })
            end,
            prefer_local = "node_modules/.bin",
          }),
          null_ls.builtins.formatting.prettier.with({
            extra_filetypes = { "php" },
            prefer_local = "node_modules/.bin",
          }),
        },
      })

      local configGroup = vim.api.nvim_create_augroup("MyLsp", { clear = true })
      vim.api.nvim_create_autocmd('BufWritePre', {
        pattern = {
          '*.lua',
          '*.php',
          '*.prisma',
          '*.go',
          '*.cjs',
          '*.mjs',
          '*.js',
          '*.cts',
          '*.mts',
          '*.ts',
          '*.jsx',
          '*.tsx'
        },
        callback = format,
        group = configGroup,
      })

      vim.diagnostic.config({ virtual_text = true })
    end,
  },
}
