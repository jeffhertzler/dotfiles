local M = {}

local loaded = false

function M.config()
  if not loaded then
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
            sources = {'nvim_lsp'},
          },
        },
        lualine_x = {
          {
            'filetype',
            colored = false,
          },
        }
      },
    })
    loaded = true
  end
end

return M

