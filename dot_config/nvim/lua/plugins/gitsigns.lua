local M = {}

function M.config()
  require('gitsigns').setup({
    current_line_blame = true,
  })
end

return M


