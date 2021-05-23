local M = {}

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
  require('compe').setup({
    enabled = true,
    autocomplete = true,
    debug = false,
    min_length = 1,
    preselect = 'always',
    throttle_time = 80,
    source_timeout = 200,
    incomplete_delay = 400,
    max_abbr_width = 100,
    max_kind_width = 100,
    max_menu_width = 100,
    documentation = true,
    source = {
      path = true,
      buffer = true,
      calc = true,
      nvim_lsp = true,
      luasnip = {
        priority = 9999,
      },
      -- nvim_lua = true,
      -- vsnip = {
      --   dup = true,
      -- },
    },
  })
end

return M
