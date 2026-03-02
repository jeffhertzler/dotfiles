return {
  {
    "NickvanDyke/opencode.nvim",
    dependencies = {
      "e-cal/opencode-tmux.nvim",
      opts = {
        focus = true,
        auto_close = false,
        allow_passthrough = true,
      },
    },
    -- stylua: ignore
    keys = {
      { '<leader>oa', function() require('opencode').ask('@this: ', { submit = true }) end, desc = 'Ask opencode', mode = { 'n', 'x', }  },
      { '<leader>oA', function() require('opencode').ask('@this') end, desc = 'Add to opencode', mode = { 'n', 'x', }  },
      { '<leader>ot', function() require('opencode').toggle() end, desc = 'Toggle embedded opencode', },
      { '<leader>op', function() require('opencode').select() end, desc = 'Select prompt', mode = { 'n', 'v', }, },
      { '<leader>on', function() require('opencode').command('session_new') end, desc = 'New session', },
      { '<leader>oy', function() require('opencode').command('messages_copy') end, desc = 'Copy last message', },
      { '<S-C-u>',    function() require('opencode').command('messages_half_page_up') end, desc = 'Scroll messages up', },
      { '<S-C-d>',    function() require('opencode').command('messages_half_page_down') end, desc = 'Scroll messages down', },
    },
  },
}
