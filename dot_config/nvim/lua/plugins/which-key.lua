local M = {}

function M.config()
  require('which-key').setup({
    layout = {
      align = 'center',
    },
  })
end

return M

