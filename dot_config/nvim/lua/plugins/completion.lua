local M = {}

function M.setup()
  vim.g.coq_settings = {
    auto_start = true,
    keymap = {
      recommended = false,
      bigger_preview = '<C-A-k>',
      jump_to_mark = '<C-A-h>',
    }
  }
end

function M.close(key)
  M.pum(key, function()
    require('compe')._close()
    require('helpers').feedkeys('<esc>')
  end)
end

function M.pum(key, alt)
  if vim.fn.pumvisible() == 1 then
    if type(alt) == 'string' then
      require('helpers').feedkeys(alt)
    else
      alt()
    end
  else
    if type(key) == 'string' then
      require('helpers').feedkeys(key)
    else
      key()
    end
  end
end


function M.config()
  local cmp = require('cmp')
  cmp.setup({
    completion = {
      completeopt = 'menu,menuone,noinsert',
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
      { name = 'luasnip' },
      { name = 'buffer' },
    },
  })
end
-- function M.config()
--   require('compe').setup({
--     enabled = true,
--     autocomplete = true,
--     debug = false,
--     min_length = 1,
--     preselect = 'always',
--     throttle_time = 80,
--     source_timeout = 200,
--     incomplete_delay = 400,
--     max_abbr_width = 100,
--     max_kind_width = 100,
--     max_menu_width = 100,
--     documentation = true,
--     source = {
--       path = true,
--       buffer = true,
--       calc = true,
--       nvim_lsp = true,
--       luasnip = {
--         priority = 9999,
--       },
--       -- nvim_lua = true,
--       -- vsnip = {
--       --   dup = true,
--       -- },
--     },
--   })
-- end

return M
