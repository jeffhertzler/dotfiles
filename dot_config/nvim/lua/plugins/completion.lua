return {
  {
    'hrsh7th/nvim-cmp',
    event = 'BufReadPre',
    dependencies = {
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'saadparwaiz1/cmp_luasnip',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-nvim-lua',
      'hrsh7th/cmp-cmdline',
      'L3MON4D3/LuaSnip',
      'rafamadriz/friendly-snippets',
      -- 'josemarluedke/ember-vim-snippets',
      -- 'Exelord/ember-snippets',
    },
    config = function()
      local cmp = require('cmp')
      local cmp_config = require('lsp-zero').defaults.cmp_config({
        experimental = {
          ghost_text = {
            hl_group = "LspCodeLens",
          },
        },
        mapping = {
          ['<C-j>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
          ['<C-k>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
          ['<CR>'] = cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true }),
        },
        window = {
          completion = cmp.config.window.bordered({
            winhighlight = 'Normal:FloatNormal,FloatBorder:FloatBorder,CursorLine:TelescopeSelection,Search:None'
          }),
          documentation = cmp.config.window.bordered({
            winhighlight = 'Normal:FloatNormal,FloatBorder:FloatBorder,CursorLine:TelescopeSelection,Search:None'
          }),
        },
      })

      table.insert(cmp_config.sources, 1, { name = 'copilot' })

      cmp.setup(cmp_config)

      local cmd_keymaps = {
        ['<C-j>'] = {
          c = function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
          end,
        },
        ['<C-k>'] = {
          c = function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end,
        },
      }

      local cmdline_opts = function(opts)
        return vim.tbl_deep_extend('force', {
          preselect = 'None',
          completion = {
            completeopt = 'menu,menuone,noinsert,noselect'
          },
          mapping = cmp.mapping.preset.cmdline(cmd_keymaps),

        }, opts or {})
      end

      cmp.setup.cmdline('/', cmdline_opts({
        sources = {
          { name = 'buffer' },
        },
      }))

      cmp.setup.cmdline('?', cmdline_opts({
        sources = {
          { name = 'buffer' },
        },
      }))

      cmp.setup.cmdline(':', cmdline_opts({
        sources = cmp.config.sources(
          {
            { name = 'path' },
          },
          {
            { name = 'cmdline' },
          }
        )
      }))
    end,
  },
  {
    'zbirenbaum/copilot.lua',
    event = 'VeryLazy',
    dependencies = {
      'zbirenbaum/copilot-cmp'
    },
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
    },
  },
  {
    'zbirenbaum/copilot-cmp',
    config = true,
  }
}
