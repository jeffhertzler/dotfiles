local helpers = {}

function helpers.dump(...)
  local objects = vim.tbl_map(vim.inspect, {...})
  print(unpack(objects))
end

function helpers.keymap(mode, lhs, rhs, opts)
  vim.api.nvim_set_keymap(mode, lhs, rhs, opts or {});
end

function helpers.get_icon(p)
  if p:sub(#p) == '/' then return '' end
  return require('nvim-web-devicons').get_icon(p, vim.fn.fnamemodify(p, ':e'), { default = true })
end

_G.dump = helpers.dump

return helpers
