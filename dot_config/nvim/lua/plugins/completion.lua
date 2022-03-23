local M = {}

function M.config()
  local cmp = require('cmp')
  cmp.setup({
    completion = {
      completeopt = 'menu,menuone,noinsert',
    },
    window = {
      completion = {
        border = 'rounded',
      },
      documentation = {
        border = 'rounded',
      },
    },
    experimental = {
      ghost_text = true
    },
    formatting = {
      format = function(_, vim_item)
        vim_item.kind = require('lspkind').presets.default[vim_item.kind] .. ' [' .. vim_item.kind .. ']'
        return vim_item
      end
    },
    snippet = {
      expand = function(args)
        require('luasnip').lsp_expand(args.body)
      end
    },
    mapping = {
      ['<C-d>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-j>'] = cmp.mapping.select_next_item(),
      ['<C-k>'] = cmp.mapping.select_prev_item(),
      ['<C-space>'] = cmp.mapping.complete(),
      ['<esc>'] = function(fallback)
        cmp.close()
        fallback()
      end,
      ['<cr>'] = cmp.mapping.confirm({ select = true }),
    },
    sources = {
      { name = 'nvim_lsp' },
      { name = 'nvim_lsp_signature_help' },
      { name = 'luasnip' },
      { name = 'buffer' },
    },
  })
end

return M
