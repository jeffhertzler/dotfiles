return {
  {
    'nvim-telescope/telescope.nvim',
    event = 'VeryLazy',
    dependencies = {
      'nvim-telescope/telescope-fzf-native.nvim',
    },
    opts = {
      defaults = {
        prompt_prefix = " ❯ ",
        selection_caret = "  ",
        entry_prefix = "  ",
        -- layout_config = {
        --   horizontal = {
        --     prompt_position = "top",
        --   },
        -- },
        mappings = {
          i = {
            ['<C-h>'] = 'which_key',
            ['<C-k>'] = 'move_selection_previous',
            ['<C-j>'] = 'move_selection_next',
          },
          n = {
            ['<C-c>'] = 'close',
          },
        },
      },
    },
    config = function(_, opts)
      local t = require('telescope')
      local tb = require('telescope.builtin')

      local utils = require('config.utils')

      local n = utils.make_keymap('n')

      n('<leader>bb', function() tb.buffers({ show_all_buffers = true }) end, 'buffers')
      n('<leader>bs', function() tb.current_buffer_fuzzy_find() end, 'search')

      n('<leader>dvv', function() tb.find_files({ search_dirs = { '~/.config/nvim' } }) end, 'files')
      n('<leader>dvV', function() tb.live_grep({ search_dirs = { '~/.config/nvim' } }) end, 'search')

      n('<leader>ff', function() tb.find_files({ hidden = true }) end, 'files')

      n('<leader>gb', function() tb.git_branches() end, 'branches')
      n('<leader>gs', function() tb.git_status() end, 'status')

      n('<leader>s ', function() tb.builtin() end, 'builtins')
      n('<leader>sb', function() tb.buffers() end, 'buffers')
      n('<leader>sc', function() tb.commands() end, 'commands')
      n('<leader>sC', function() tb.command_history() end, 'command history')
      n('<leader>sd', function() tb.live_grep({ cwd = '%:p:h' }) end, 'directory')
      n('<leader>sD', function() tb.find_files({ cwd = '%:p:h', hidden = true }) end, 'directory (files)')
      n('<leader>sf', function() tb.find_files({ hidden = true }) end, 'files')

      n('<leader>sgb', function() tb.git_branches() end, 'branches')
      n('<leader>sgc', function() tb.git_commits() end, 'commits')
      n('<leader>sgC', function() tb.git_commits() end, 'commits (buffer)')
      n('<leader>sgs', function() tb.git_commits() end, 'status')

      n('<leader>sh', function() tb.help_tags() end, 'help')
      n('<leader>sH', function() tb.highlights() end, 'highlights')
      n('<leader>sm', function() tb.marks() end, 'marks')
      n('<leader>sp', function() tb.live_grep() end, 'project')
      n('<leader>sr', function() tb.registers() end, 'registers')
      n('<leader>ss', function() tb.live_grep() end, 'search')
      n('<leader>sS', function() tb.current_buffer_fuzzy_find() end, 'search (buffer)')
      n('<leader>st', function() tb.grep_string() end, 'this')

      n('<leader>tr', function() tb.resume() end, 'resume')

      n('<leader>/', function() tb.current_buffer_fuzzy_find() end, 'search (buffer)')

      t.setup(opts)
    end,
  },
  {
    'nvim-telescope/telescope-fzf-native.nvim',
    build = 'make',
    config = function()
      require('telescope').load_extension('fzf')
    end,
  },
}
