return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    key_labels = { ['<leader>'] = 'SPC' },
    layout = {
      align = 'center',
    },
  },
  config = function(_, opts)
    local wk = require('which-key')

    wk.setup(opts)

    wk.register({
      mode = { 'n' },
      g = { name = 'go/git' },
      ['<leader>'] = {
        name = 'leader',
        b = { name = 'buffer' },
        c = {
          name = 'code',
          d = { name = 'diagnostics' },
          l = { name = 'lens' },
        },
        d = {
          name = 'dotfiles',
          t = { name = 'tmux' },
          v = { name = 'vim' },
          z = { name = 'zsh' },
        },
        f = { name = 'file' },
        g = { name = 'go/git' },
        p = { name = 'plugins' },
        q = { name = 'quit' },
        s = { name = 'search' },
        t = { name = 'toggle' },
        w = {
          name = 'window',
          s = { name = 'split' },
        },
      },
    })

    wk.register({
      mode = { 'x' },
      ['<leader>'] = {
        c = {
          name = 'code',
        },
      },
    })
  end
}
