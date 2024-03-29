local M = {}

function M.setup()
  vim.g.dashboard_default_executive = 'telescope'
  vim.g.dashboard_custom_shortcut = {
    last_session       = 'SPC s l',
    find_history       = 'SPC f h',
    find_file          = 'SPC f f',
    new_file           = 'SPC f n',
    change_colorscheme = 'SPC t c',
    find_word          = 'SPC f a',
    book_marks         = 'SPC f b',
 }
end

return M
