local M = {}

function M.setup()
  -- rename these so plugin commands don't conflict
  vim.g.close_buffers_bdelete_command = 'CBdelete'
  vim.g.close_buffers_bwipeout_command = 'CBwipeout'
end

return M
