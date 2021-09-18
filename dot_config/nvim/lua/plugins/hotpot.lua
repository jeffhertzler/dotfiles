local M = {}

function M.setup()
  local start_path = require('plugins.packer').start_path
  local hotpot_path = start_path .. '/hotpot.nvim'
  if vim.fn.empty(vim.fn.glob(hotpot_path)) > 0 then
    local git = 'git clone https://github.com/rktjmp/hotpot.nvim ' .. hotpot_path
    vim.fn.system(git)
  end
end

return M
