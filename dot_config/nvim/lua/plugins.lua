local function packadd()
  return pcall(vim.cmd, [[packadd packer.nvim]])
end

if not packadd() then
  local dir = vim.fn.stdpath('data') .. '/site/pack/packer/opt/'

  vim.fn.mkdir(dir, 'p')

  local git = 'git clone https://github.com/wbthomason/packer.nvim ' .. dir .. '/packer.nvim'

  vim.fn.system(git)

  packadd()
end

local packer = require('packer')
local util = require('packer.util')

return packer.startup {
  function(use)
    use {'wbthomason/packer.nvim', opt = true}

    -- motions
    use {'tpope/vim-commentary'}
    use {'tpope/vim-eunuch'}
    use {'tpope/vim-surround'}
    use {'tpope/vim-repeat'}
    use {'justinmk/vim-sneak'}
    use {'andymass/vim-matchup'}

    -- navigation
    use {'justinmk/vim-dirvish',
      requires = {
        {'roginfarrer/vim-dirvish-dovish', branch = 'main'},
      }
    }
    use {'christoomey/vim-tmux-navigator'}
    use {'liuchengxu/vim-which-key'}
    use {
      'nvim-telescope/telescope.nvim',
      -- 'oberblastmeister/telescope.nvim',
      -- branch = 'async',
      requires = {
        {'nvim-lua/popup.nvim'},
        {'nvim-lua/plenary.nvim'},
        {'kyazdani42/nvim-web-devicons'},
      	-- {'nvim-telescope/telescope-fzf-writer.nvim'},
      }
    }
    -- use {
    --   'nvim-telescope/telescope-frecency.nvim',
    --   requires = {
    --     {'tami5/sql.nvim'},
    --     {'nvim-telescope/telescope.nvim'},
    --   },
    --   config = function()
    --     require('telescope').load_extension('frecency')
    --   end
    -- }
    use {
      'nvim-telescope/telescope-fzy-native.nvim',
      requires = {
        {'nvim-telescope/telescope.nvim'},
      },
      config = function()
        require('telescope').load_extension('fzy_native')
      end
    }
    use {'kyazdani42/nvim-tree.lua',
      requires = {
        {'kyazdani42/nvim-web-devicons'},
      }
    }

    -- git
    use {'rhysd/git-messenger.vim'}
    -- use {'airblade/vim-gitgutter'}
    use {
      'lewis6991/gitsigns.nvim',
      requires = {
        {'nvim-lua/plenary.nvim'},
      },
    }

    -- buffers
    use {'moll/vim-bbye'}
    use {'Asheq/close-buffers.vim'}

    -- wrappers
    use {'kdheepak/lazygit.nvim'}
    use {'numtostr/FTerm.nvim'}

    -- extras
    use {'mhinz/vim-startify'}

    -- treesitter
    use {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'}

    -- indenting
    use {'editorconfig/editorconfig-vim'}
    use {'tpope/vim-sleuth'}

    -- CoC
    use {'neoclide/coc.nvim', branch = 'release', run = ':CocUpdate'}

    -- javascript/typescript
    -- use {'jparise/vim-graphql'}

    -- ember
    use {'joukevandermaas/vim-ember-hbs'}
    use {'josemarluedke/ember-vim-snippets'}

    -- langs
    use {'mattn/emmet-vim'}
    use {'neoclide/jsonc.vim'}
    use {'leafOfTree/vim-svelte-plugin'}

    -- visuals
    use {'dracula/vim', as = 'dracula'}
    use {'vim-airline/vim-airline'}
    -- use {'ryanoasis/vim-devicons'}
    -- {'kyazdani42/nvim-web-devicons'}
  end,
  config = {
    display = {
      open_fn = util.float
    }
  }
}
