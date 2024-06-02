local mk = require('config.utils').make_keymap
local n = mk('n')

local M = {
  'akinsho/toggleterm.nvim',
}

M.event = 'VeryLazy'

M.config = function()
  require('toggleterm').setup()
  M.Terminal = require('toggleterm.terminal').Terminal

  M.lazygit = M.Terminal:new({
    cmd = "lazygit -ucf ~/.config/jesseduffield/lazygit/nvim-config.yml",
    dir = "git_dir",
    direction = "float",
    hidden = true,
    persist_size = false,
    float_opts = {
      border = "double",
    },
    highlights = {
      NormalFloat = {
        link = 'NormalFloat',
      },
    },
  })

  n('<leader>gg', function() M.lazygit:toggle() end, 'gui')
end

return M
