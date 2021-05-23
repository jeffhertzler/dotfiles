local M = {}

M.border = {'╭','─','╮','│','╯','─','╰','│'}

function M.keymap(mode, lhs, rhs, opts)
  vim.api.nvim_set_keymap(mode, lhs, rhs, opts or {});
end

function M.t(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end

function M.feedkeys(str)
  return vim.api.nvim_feedkeys(M.t(str), 'n', true)
end

function M.dump(...)
  local objects = vim.tbl_map(vim.inspect, {...})
  print(unpack(objects))
end

_G.dump = M.dump

return M
