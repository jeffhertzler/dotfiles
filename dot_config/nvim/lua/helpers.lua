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

function helpers.map_from_table(mode, map, lhs, which_key_map)
  which_key_map = which_key_map or {}
  if not map then return which_key_map end

  for k, v in pairs(map) do
    if v.keys then
      which_key_map[k] = { name = '+'..v.name }
      which_key_map[k] = helpers.map_from_table(mode, v.keys, lhs..k, which_key_map[k])
    else
      which_key_map[k] = v.ignore and 'which_key_ignore' or v.name
      if v.action then helpers.keymap(mode, lhs..k, v.action, v.opts) end
    end
  end

  return which_key_map
end

_G.dump = helpers.dump

return helpers
