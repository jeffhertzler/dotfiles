local M = {}

function M.packadd()
  return pcall(vim.cmd, [[packadd packer.nvim]])
end

M.compile_path = vim.fn.stdpath('data') .. '/site/plugin/packer_compiled.lua'
M.pack_path = vim.fn.stdpath('data') .. '/site/pack/packer/'
M.opt_path = M.pack_path .. 'opt/'
M.start_path = M.pack_path .. 'start/'

function M.setup()
  if not M.packadd() then
    vim.fn.mkdir(M.opt_path, 'p')
    local git = 'git clone https://github.com/wbthomason/packer.nvim ' .. M.opt_path .. '/packer.nvim'
    vim.fn.system(git)
    M.packadd()
  end
end

function M.open_fn()
  return require('packer.util').float({ border = require('helpers').border })
end

return M
