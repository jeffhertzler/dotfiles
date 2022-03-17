local M = {}

local loaded = false

function M.config()
  if not loaded then

    local status = require('nvim-spotify').status
    status:start()

    require('lualine').setup({
      options = {
        theme = 'tokyonight'
      },
      sections = {
        lualine_c = {
          {
            'filename',
            file_status = true,
            path = 1,
          },
          {
            'diagnostics',
            sources = {'nvim_diagnostic'},
          },
        },
        lualine_x = {
          {
            'filetype',
            colored = false,
          },
        },
        lualine_y = {
          status.listen,
        },
      },
    })
    loaded = true
  end
end

return M

