local actions = require('lir.actions')
local mark_actions = require('lir.mark.actions')
local clipboard_actions = require('lir.clipboard.actions')

local M = {}

function M.config()
  require('lir').setup({
    devicons_enable = true,
    hide_cursor = true,
    show_hidden_files = true,
    mappings = {
      ['<cr>'] = actions.edit,
      ['<c-m-s>'] = actions.split,
      ['<c-m-v>'] = actions.vsplit,
      ['<c-m-t>'] = actions.tabedit,

      ['-'] = actions.up,
      ['q'] = actions.quit,

      ['K'] = actions.mkdir,
      ['N'] = actions.newfile,
      ['R'] = actions.rename,
      ['@'] = actions.cd,
      ['Y'] = actions.yank_path,
      ['.'] = actions.toggle_show_hidden,
      ['D'] = actions.delete,

      ['J'] = function()
        mark_actions.toggle_mark()
        vim.cmd('normal! j')
      end,
      ['C'] = clipboard_actions.copy,
      ['X'] = clipboard_actions.cut,
      ['P'] = clipboard_actions.paste,
    },
    float = {
      borderchars = require('helpers').border,
      border = true,
      size_percentage = 0.8,
      winblend = 0,
    },
  })
end

return M
