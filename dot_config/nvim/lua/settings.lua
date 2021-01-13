-- don't load these built-in plugins
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1

vim.g.mapleader = ' '

-- make sure neovim can find my node version when using volta
vim.g.node_host_prog = vim.fn.trim(vim.fn.system('volta which neovim-node-host'))

-- this was breaking when exiting autocomplete (could no longer see cursor)
vim.g.coc_disable_transparent_cursor = 1

-- rename these so plugin commands don't conflict
vim.g.close_buffers_bdelete_command = 'CBdelete'
vim.g.close_buffers_bwipeout_command = 'CBwipeout'

vim.g.vim_svelte_plugin_use_typescript = 1
vim.g.vim_svelte_plugin_use_sass = 1

vim.g.nvim_tree_width_allow_resize = 1
vim.g.nvim_tree_width = 50
vim.g.nvim_tree_side = 'right'
vim.g.nvim_tree_icons = {
  default = ' ',
}

-- airline
-- vim.g.airline_statusline_ontop = 1
vim.g.airline_powerline_fonts = 1

-- don't stop at sign column
vim.g.which_key_disable_default_offset = 1
-- allow fallthrough commands (gg)
vim.g.which_key_fallback_to_native_key = 1

vim.o.clipboard = 'unnamedplus'
vim.o.completeopt = 'menuone,noinsert,noselect'
vim.o.hidden = true
vim.o.shortmess = vim.o.shortmess .. 'c'
vim.o.showmode = false;
vim.o.termguicolors = true
vim.o.timeoutlen = 500

-- do i really want to turn these off or can I just move where they live?
vim.o.backup = false
vim.o.writebackup = false
vim.o.swapfile = false

vim.wo.list = true
vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.signcolumn = 'yes:1'

vim.bo.autoindent = true
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.bo.softtabstop = 2
vim.bo.tabstop = 2

vim.cmd [[colorscheme dracula]]
-- vim.cmd [[highlight link WhichKeyFloating DraculaSelection]]

-- coc
vim.g.coc_global_extensions = {
  'coc-css',
  'coc-ember',
  'coc-eslint',
  -- 'coc-git',
  -- 'coc-graphql',
  'coc-highlight',
  'coc-html',
  'coc-java',
  'coc-json',
  'coc-lua',
  'coc-markdownlint',
  'coc-prettier',
  'coc-rust-analyzer',
  'coc-sh',
  'coc-snippets',
  'coc-svelte',
  'coc-tsserver',
  'coc-vimlsp',
  'coc-yaml'
}

-- telescope
require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ["<c-k>"] = require('telescope.actions').move_selection_previous,
        ["<c-j>"] = require('telescope.actions').move_selection_next,
      }
    }
  },
  extensions = {
    fzf_writer = {
      minimum_grep_characters = 2,
      minimum_files_characters = 2,
      use_highlighter = true,
    }
  }
}

-- treesitter
require('nvim-treesitter.configs').setup {
  ensure_installed = "maintained",
  highlight = {
    enable = true,
  },
  indentation = {
    enable = true,
  },
}

-- gitsigns
require('gitsigns').setup {
  signs = {
    add          = {hl = 'DiffAdd'   , text = '│'},
    change       = {hl = 'DiffChange', text = '│'},
    delete       = {hl = 'DraculaRed', text = '_'},
    topdelete    = {hl = 'DraculaRed', text = '‾'},
    changedelete = {hl = 'DiffChange', text = '~'},
  },
}

-- autorecompile packer on save
vim.cmd [[autocmd BufWritePost plugins.lua PackerCompile]]

-- autocreate non-existent subdirectories when saving a new buffer
vim.cmd [[au BufWritePre,FileWritePre * silent! call mkdir(expand('<afile>:p:h'), 'p')]]

-- use jsonc for known files
vim.cmd [[autocmd BufRead,BufNewFile jsconfig.json,jsconfig*.json,tsconfig.json,tsconfig*.json,*.json5 set filetype=jsonc]]
