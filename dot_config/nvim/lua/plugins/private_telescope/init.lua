local M = {}

function M.config()
  require('telescope').setup({
    defaults = {
      mappings = {
        i = {
          ['<C-k>'] = require('telescope.actions').move_selection_previous,
          ['<C-j>'] = require('telescope.actions').move_selection_next,
        },
        n = {
          ['<C-c>'] = require('telescope.actions').close,
        },
      },
    },
    extensions = {
      fzf = {
        override_generic_sorter = true,
        override_file_sorter = true,
      },
    },
  })
end

return M
