local M = {}

function M.config()
  local cmp = require('cmp')

  cmp.setup({
    window = {
      completion = cmp.config.window.bordered(),
      documentation = cmp.config.window.bordered(),
    },
    experimental = {
      ghost_text = true
    },
    formatting = {
      format = function(entry, vim_item)
        if entry.source.name == 'copilot' then
          vim_item.kind = ' [Copilot]';
        else
          vim_item.kind = require('lspkind').presets.default[vim_item.kind] .. ' [' .. vim_item.kind .. ']'
        end
        return vim_item
      end
    },
    snippet = {
      expand = function(args)
        require('luasnip').lsp_expand(args.body)
      end
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-d>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-j>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
      ['<C-k>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
      ['<C-l>'] = cmp.mapping.confirm({
        behavior = cmp.ConfirmBehavior.Replace,
        select = true,
      }),
      ['<CR>'] = cmp.mapping.confirm({
        behavior = cmp.ConfirmBehavior.Replace,
      }),
      ['<esc>'] = function(fallback)
        cmp.close()
        fallback()
      end,
    }),
    sources = cmp.config.sources({
      { name = 'copilot', group_index = 2 },
      { name = 'nvim_lsp', group_index = 2 },
      { name = 'nvim_lsp_signature_help', group_index = 2 },
      { name = 'luasnip', group_index = 2 },
      { name = 'buffer', group_index = 2 },
    }),
    sorting = {
      priority_weight = 2,
      comparators = {
        require("copilot_cmp.comparators").prioritize,
        require("copilot_cmp.comparators").score,

        -- Below is the default comparitor list and order for nvim-cmp
        cmp.config.compare.offset,
        -- cmp.config.compare.scopes, --this is commented in nvim-cmp too
        cmp.config.compare.exact,
        cmp.config.compare.score,
        cmp.config.compare.recently_used,
        cmp.config.compare.locality,
        cmp.config.compare.kind,
        cmp.config.compare.sort_text,
        cmp.config.compare.length,
        cmp.config.compare.order,
      }
    }
  })

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

  cmp.setup.cmdline('/', {
    mapping = cmp.mapping.preset.cmdline(cmd_keymaps);
    sources = {
      { name = 'buffer' }
    }
  })

  cmp.setup.cmdline('?', {
    mapping = cmp.mapping.preset.cmdline(cmd_keymaps);
    sources = {
      { name = 'buffer' }
    }
  })

  cmp.setup.cmdline(':', {
    mapping = cmp.mapping.preset.cmdline(cmd_keymaps);
    sources = cmp.config.sources({
      { name = 'path' }
    }, {
      { name = 'cmdline' }
    })
  })
end

return M
