local mk = require('config.utils').make_keymap
local n = mk('n')
local o = mk('o')
local x = mk('x')
local ox = mk({ 'o', 'x' })

return {
  -- 'mrjones2014/legendary.nvim',
  -- 'ThePrimeagen/harpoon',
  -- 'sindrets/diffview.nvim',
  -- 'tpope/vim-sleuth',

  -- TODO: try me!
  -- 'b0o/SchemaStore.nvim',
  -- 'nvim-pack/nvim-spectre',
  -- 'smjonas/inc-rename.nvim',

  -- {
  --   'NvChad/nvim-colorizer.lua',
  --   event = 'BufReadPre',
  --   config = true,
  -- },
  -- {
  --   'ellisonleao/glow.nvim',
  --   cmd = { 'Glow' },
  --   opts = {
  --     border = 'solid',
  --     width = 999999,
  --     height = 999999,
  --     width_ratio = 0.7,
  --     height_ratio = 0.7,
  --     style = '~/dev/catppuccin/glamour/themes/mocha.json',
  --   },
  -- },

  {
    'johmsalas/text-case.nvim',
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("textcase").setup({})
      require("telescope").load_extension("textcase")
    end,
    keys = {
      "ga",
      { "ga.", "<cmd>TextCaseOpenTelescope<CR>", mode = { "n", "x" }, desc = "Telescope" },
    },
    cmd = {
      "Subs",
      "TextCaseOpenTelescope",
      "TextCaseOpenTelescopeQuickChange",
      "TextCaseOpenTelescopeLSPChange",
      "TextCaseStartReplacingCommand",
    },
    lazy = false,
  },

  {
    'Asheq/close-buffers.vim',
    cmd = { 'CBdelete', 'CBwipeout' },
    init = function()
      vim.g.close_buffers_bdelete_command = 'CBdelete'
      vim.g.close_buffers_bwipeout_command = 'CBwipeout'
    end,
    keys = {
      { '<leader>bD', '<cmd>CBdelete other<cr>', desc = 'delete (others)' },
    }
  },
  {
    'moll/vim-bbye',
    cmd = { 'Bdelete', 'Bwipeout' },
    keys = {
      { '<leader>bd', '<cmd>Bdelete<cr>', desc = 'delete' },
    }
  },
  {
    'ggandor/leap.nvim',
    config = function()
      local leap = require('leap')
      local gew = require('leap.util').get_enterable_windows

      leap.setup({
        highlight_unlabeled_phase_one_targets = true
      })

      n('z', function() leap.leap({}) end, 'leap')
      o('z', function() leap.leap({ offset = 1 }) end, 'leap (inclusive)')
      x('z', function() leap.leap({}) end, 'leap (inclusive)')

      n('Z', function() leap.leap({ backward = true }) end, 'leap (backwards)')
      ox('Z', function() leap.leap({ backward = true }) end, 'leap (inclusive, backwards)')

      ox('x', function() leap.leap({ offset = -1, inclusive_op = true }) end, 'leap (exclusive)')
      ox('X', function() leap.leap({ backward = true, offset = 1 }) end, 'leap (exclusive, backwards)')

      n('gz', function() leap.leap({ target_windows = gew() }) end, 'leap (other window)')
    end,
  },
  {
    'ggandor/flit.nvim',
    event = 'VeryLazy',
    dependencies = {
      'ggandor/leap.nvim',
    },
    config = true,
  },
  {
    'folke/neodev.nvim',
  },
  {
    'neovim/nvim-lspconfig',
  },
  {
    'williamboman/mason.nvim',
    dependencies = {
      'williamboman/mason-lspconfig.nvim',
    },
  },
  {
    'tpope/vim-abolish',
    event = 'BufReadPre'
  },
  {
    'tpope/vim-commentary', -- TODO: try one of the newer lua alternatives
    event = 'BufReadPre'
  },
  {
    'tpope/vim-eunuch',
    event = 'BufReadPre'
  },
  {
    'kylechui/nvim-surround',
    event = 'VeryLazy',
    config = true,
  },
  {
    'tpope/vim-repeat',
    event = 'BufReadPre'
  },

  {
    'rmagatti/alternate-toggler',
    cmd = 'ToggleAlternate',
    keys = {
      { '<leader>tb', '<cmd>ToggleAlternate<cr>', desc = 'boolean' }
    },
  },
  {
    'christoomey/vim-tmux-navigator', -- TODO: look into lua versions
    dependencies = {
      'ojroques/nvim-osc52',
    },
    event = 'VeryLazy',
  },
  {
    'kevinhwang91/nvim-bqf',
    event = 'VeryLazy',
    dependencies = {
      'junegunn/fzf',
    }
  },
  {
    'folke/lazy.nvim',
    lazy = false,
  },
  {
    'andymass/vim-matchup',
    event = 'BufReadPre',
  },
  -- {
  --   'kdheepak/lazygit.nvim',
  --   cmd = 'LazyGit',
  --   keys = {
  --     { '<leader>gc', '<cmd>LazyGitFilter<cr>', desc = 'commits' },
  --     { '<leader>gc', '<cmd>LazyGitFilterCurrentFile<cr>', desc = 'commits (buffer)' },
  --     { '<leader>gg', '<cmd>LazyGit<cr>', desc = 'gui' },
  --   },
  -- },
  {
    'folke/todo-comments.nvim',
    event = 'BufReadPre',
    config = true,
  },
  {
    'folke/trouble.nvim',
    cmd = { "TroubleToggle", "Trouble" },
    opts = {
      use_diagnostic_signs = true
    },
  },
  {
    'numtostr/FTerm.nvim',
    opts = {
      border = 'solid',
      hl = 'NormalFloat'
    }
  },
  -- {
  --   'KadoBOT/nvim-spotify',
  --   cmd = { 'Spotify', 'SpotifyDevices' },
  --   config = true,
  --   build = 'make',
  -- },
  {
    'rhysd/git-messenger.vim',
    cmd = 'GitMessenger',
    keys = {
      { 'gm',         '<cmd>GitMessenger<cr>', desc = 'messenger' },
      { '<leader>gm', '<cmd>GitMessenger<cr>', desc = 'messenger' },
    },
  },
  {
    'lewis6991/gitsigns.nvim',
    event = 'BufReadPre',
    opts = {
      current_line_blame = true,
      trouble = true,
    },
  },
  {
    'max397574/better-escape.nvim',
    event = 'InsertEnter',
    opts = {
      mapping = { 'fd' },
    },
  },
  {
    'nvim-lua/plenary.nvim',
    config = function()
      require('plenary.filetype').add_file('extras')
    end,
  },
  {
    'nvim-tree/nvim-web-devicons',
    config = true,
    -- opts = {
    --   override = {
    --     lir_folder_icon = {
    --       icon = "",
    --       color = "#7ebae4",
    --       name = "LirFolderNode",
    --     },
    --   },
    --   setup = true,
    -- },
  },
  -- {
  --   'onsails/lspkind-nvim',
  --   config = function()
  --     require('lspkind').init()
  --   end,
  -- },
  {
    'rcarriga/nvim-notify',
    event = 'VeryLazy',
    config = function()
      vim.notify = require('notify')
    end,
  },
  {
    'stevearc/dressing.nvim',
    event = 'VeryLazy',
    config = function()
      require('dressing').setup({
        input = {
          insert_only = false,
        },
        select = {
          telescope = require('telescope.themes').get_cursor(),
        },
      })
    end,
    dependencies = { 'nvim-telescope/telescope.nvim' },
  },
  {
    'stevearc/oil.nvim',
    lazy = false,
    config = function()
      local oil = require('oil')
      oil.setup({
        keymaps = {
          ['<C-h>'] = false,
          ['<C-l>'] = false,
          ['RR'] = 'actions.refresh',
          ['<C-A-j>'] = 'actions.select_split',
          ['<C-A-l>'] = 'actions.select_vsplit',
        },
        skip_confirm_for_simple_edits = true,
        view_options = {
          show_hidden = true,
        },
      })
      vim.keymap.set("n", "-", oil.open, { desc = "Open parent directory" })
    end,
  },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = true,
  },
}
