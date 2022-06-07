local M = {}

function M.config()
  local devicons = require('nvim-web-devicons')
  devicons.setup({ default = true });
  devicons.set_icon({
    lir_folder_icon = {
      icon = "",
      color = "#7ebae4",
      name = "LirFolderNode"
    }
  })
end

return M
