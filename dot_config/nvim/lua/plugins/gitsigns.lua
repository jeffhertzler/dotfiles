local M = {}

function M.config()
  require('gitsigns').setup({
    signs = {
      add          = {hl = 'DiffAdd'   , text = '│'},
      change       = {hl = 'DiffChange', text = '│'},
      delete       = {hl = 'DraculaRed', text = '_'},
      topdelete    = {hl = 'DraculaRed', text = '‾'},
      changedelete = {hl = 'DiffChange', text = '~'},
    },
  })
end

return M


