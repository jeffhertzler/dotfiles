local M = {}

function M.packadd()
  return pcall(vim.cmd, [[packadd packer.nvim]])
end

function M.setup()
  if not M.packadd() then
    local dir = vim.fn.stdpath('data') .. '/site/pack/packer/opt/'
    vim.fn.mkdir(dir, 'p')
    local git = 'git clone https://github.com/wbthomason/packer.nvim ' .. dir .. '/packer.nvim'
    vim.fn.system(git)
    M.packadd()
  end
end

function M.open_fn()
  return require('packer.util').float({ border = require('helpers').border })
end

return M
