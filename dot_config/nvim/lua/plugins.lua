-- require('plugins.packer').setup()
-- require('plugins.hotpot').setup()

require('packer').startup {
  function(use)
    use { 'wbthomason/packer.nvim', opt = true }
    use { 'dstein64/vim-startuptime' }
    use { 'lewis6991/impatient.nvim' }

    -- there's a built-in thing for this now, but it doesn't fully replace the old filetype.vim yet
    use { 'nathom/filetype.nvim' }

    use { 'antoinemadec/FixCursorHold.nvim' }
    -- use {
    --   'rktjmp/hotpot.nvim',
    --   config = function() require('hotpot') end,
    -- }

    use {
      'nvim-lua/plenary.nvim',
      config = function() require('plugins.plenary').config() end,
    }
    use { 'nvim-lua/popup.nvim' }
    use {
      'stevearc/dressing.nvim',
      config = function()
        require('dressing').setup({
          input = {
            insert_only = false,
          },
          select = {
            telescope = require('telescope.themes').get_cursor(),
          },
        })
      end
    }

    use {
      'kyazdani42/nvim-web-devicons',
      config = function() require('plugins.icons').config() end,
    }

    use { 'nanotee/nvim-lua-guide' }
    use { 'folke/lua-dev.nvim' }

    use {
      'max397574/better-escape.nvim',
      config = function() require('better_escape').setup({ mapping = { "fd" } }) end,
    }

    use {
      'KadoBOT/nvim-spotify',
      config = function() require('nvim-spotify').setup({}) end,
      run = 'make'
    }

    use {
      'windwp/nvim-autopairs',
      config = function() require('nvim-autopairs').setup() end,
    }

    -- motions
    use { 'tpope/vim-commentary' }
    use { 'tpope/vim-eunuch' }
    use { 'tpope/vim-surround' }
    use { 'tpope/vim-repeat' }
    use { 'andymass/vim-matchup' }
    use { 'ggandor/lightspeed.nvim' }

    use { 'rmagatti/alternate-toggler' }

    -- tmux
    use { 'christoomey/vim-tmux-navigator' }
    use { 'ojroques/vim-oscyank' }

    -- lsp
    use { 'neovim/nvim-lspconfig' }
    use {
      'williamboman/nvim-lsp-installer',
      config = function() require('plugins.lsp').config() end,
    }
    use {
      'onsails/lspkind-nvim',
      config = function() require('plugins.lsp.kind').config() end,
    }
    use { 'jose-elias-alvarez/null-ls.nvim' }
    use { 'jose-elias-alvarez/nvim-lsp-ts-utils' }
    use { 'kosayoda/nvim-lightbulb' }
    -- use {
    --   'j-hui/fidget.nvim',
    --   config = function() require('fidget').setup() end,
    -- }

    use {
      'folke/trouble.nvim',
      config = function() require('trouble').setup() end,
    }
    use {
      'folke/todo-comments.nvim',
      config = function() require('todo-comments').setup() end,
    }
    use { 'kevinhwang91/nvim-bqf' }
    use { 'junegunn/fzf' }

    use {
      'rcarriga/nvim-notify',
      config = function() vim.notify = require('notify') end,
    }

    -- use { 'github/copilot.vim' }
    use {
      'zbirenbaum/copilot.lua',
      event = { "VimEnter" },
      config = function()
        vim.defer_fn(function()
          require("copilot").setup({
            -- cmp = {
            --   enabled = true,
            --   method = "getCompletionsCycling",
            -- },
            -- panel = {
            --   enabled = true,
            -- }
          })
        end, 100)
      end,
    }

    use {
      'zbirenbaum/copilot-cmp',
      module = 'copilot_cmp',
    }
    use { 'hrsh7th/cmp-nvim-lsp' }
    use { 'hrsh7th/cmp-nvim-lsp-signature-help' }
    use { 'hrsh7th/cmp-buffer' }
    use { 'hrsh7th/cmp-path' }
    use { 'hrsh7th/cmp-cmdline' }
    use { 'saadparwaiz1/cmp_luasnip' }
    use {
      'hrsh7th/nvim-cmp',
      config = function() require('plugins.completion').config() end,
    }
    -- use {'mfussenegger/nvim-jdtls'}

    -- debugging
    -- use {'mfussenegger/nvim-dap'}

    -- navigation
    use {
      'tamago324/lir.nvim',
      after = { 'nvim-web-devicons' },
      config = function() require('plugins.lir').config() end,
    }
    use {
      'folke/which-key.nvim',
      config = function() require('plugins.which-key').config() end,
    }
    use { 'mrjones2014/legendary.nvim' }

    use {
      'nvim-telescope/telescope.nvim',
      config = function() require('plugins.telescope').config() end,
    }
    use { 'nvim-telescope/telescope-github.nvim' }
    -- use { "natecraddock/telescope-zf-native.nvim" } -- TODO: try this
    use {
      'nvim-telescope/telescope-fzf-native.nvim',
      run = 'make',
      config = function() require('plugins.telescope.fzf').config() end,
    }
    -- use {
    --   'kyazdani42/nvim-tree.lua',
    --   config = function() require('nvim-tree').setup() end,
    -- }

    -- git
    use { 'rhysd/git-messenger.vim' }
    use {
      'lewis6991/gitsigns.nvim',
      config = function() require('plugins.gitsigns').config() end,
    }
    use {
      'sindrets/diffview.nvim',
      config = function() require('diffview').setup() end,
    }
    -- use {
    --   'TimUntersberger/neogit',
    --   config = function() require('plugins.neogit').config() end,
    -- }

    -- buffers
    use { 'moll/vim-bbye' }
    use {
      'Asheq/close-buffers.vim',
      setup = function() require('plugins.close-buffers').setup() end,
    }

    -- wrappers
    use { 'kdheepak/lazygit.nvim' }
    use {
      'numtostr/FTerm.nvim',
      config = function() require('plugins.term').config() end,
    }

    -- extras
    -- use {
    --   'glepnir/dashboard-nvim',
    --   setup = function() require('plugins.dashboard').setup() end,
    -- }

    -- treesitter
    use {
      'nvim-treesitter/nvim-treesitter',
      run = ':TSUpdate',
      config = function() require('plugins.treesitter').config() end,
    }
    use { 'nvim-treesitter/nvim-treesitter-textobjects' }
    -- use {
    --   'windwp/nvim-ts-autotag',
    --   config = function() require('plugins.treesitter.autotag').config() end,
    -- }
    use { 'nvim-treesitter/playground' }

    -- indenting
    use {
      'editorconfig/editorconfig-vim',
      setup = function() require('plugins.editorconfig').setup() end,
    }
    use { 'tpope/vim-sleuth' }

    -- ember
    -- use {'josemarluedke/ember-vim-snippets'}
    use { 'Exelord/ember-snippets', run = 'npm install && npm run build' }
    use {
      'L3MON4D3/LuaSnip',
      config = function() require('plugins.snippets').config() end,
    }

    -- langs
    use { 'mattn/emmet-vim' }
    use { 'neoclide/jsonc.vim' }
    use { 'leafOfTree/vim-svelte-plugin' }
    -- use { 'WhoIsSethDaniel/goldsmith.nvim' }
    use {
      'unisonweb/unison',
      branch = 'trunk',
      rtp = 'editor-support/vim',
    }

    -- visuals
    -- use { 'folke/tokyonight.nvim' }
    use {
      'catppuccin/nvim',
      as = 'catppuccin',
      config = function() require('plugins.theme').catppuccin() end
    }
    use { 'b0o/incline.nvim', }
    -- use {
    --   'nvim-lualine/lualine.nvim',
    --   config = function() require('plugins.statusline').config() end,
    -- }
    use { 'feline-nvim/feline.nvim' }
    use {
      'lukas-reineke/indent-blankline.nvim',
      setup = function() require('plugins.indent').setup() end,
    }
  end,
  config = {
    compile_path = require('plugins.packer').compile_path,
    display = {
      open_fn = require('plugins.packer').open_fn,
    },
    profile = {
      enable = true,
      threshold = 1,
    },
  },
}
