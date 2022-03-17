local M = {}

function M.setup()
  vim.g.indent_blankline_char = '│'
  vim.g.indent_blankline_use_treesitter = true
  vim.g.indent_blankline_show_current_context = false
  vim.g.indent_blankline_filetype_exclude = {'gitmessengerpopup', 'help', 'packer', 'lspinfo'}
end

return M
