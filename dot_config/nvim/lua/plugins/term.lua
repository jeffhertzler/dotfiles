local M = {}

function M.config()
  require('FTerm').setup({ border = require('helpers').border })
end

return M
