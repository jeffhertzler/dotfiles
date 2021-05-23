local M = {}

function M.setup()
  vim.g.nvim_tree_width_allow_resize = 1
  vim.g.nvim_tree_width = 50
  vim.g.nvim_tree_side = 'right'
  vim.g.nvim_tree_icons = {
    default = '',
  }
end

return M
