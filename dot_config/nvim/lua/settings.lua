-- don't load these built-in plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1

vim.g.mapleader = ' '

-- make sure neovim can find my node version when using volta
vim.g.node_host_prog = vim.fn.trim(vim.fn.system('volta which neovim-node-host'))

vim.o.clipboard = 'unnamedplus'
vim.o.completeopt = 'menuone,noselect,noinsert'
vim.o.hidden = true
vim.o.shortmess = vim.o.shortmess .. 'c'
vim.o.showmode = false;
vim.o.termguicolors = true
vim.o.timeoutlen = 500

vim.o.ignorecase = true
vim.o.smartcase = true

-- do i really want to turn these off or can I just move where they live?
vim.o.backup = false
vim.o.writebackup = false
vim.o.swapfile = false

vim.wo.list = true
vim.wo.number = true
-- vim.wo.relativenumber = true
vim.wo.signcolumn = 'yes:1'
vim.wo.colorcolumn = ""

vim.bo.autoindent = true
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.bo.softtabstop = 2
vim.bo.tabstop = 2

vim.cmd [[filetype plugin on]]
vim.cmd [[colorscheme tokyonight]]

vim.cmd [[
  augroup TmuxYankAuto
    autocmd!
    autocmd TextYankPost * if v:event.operator is 'y' && v:event.regname is '' | OSCYankReg + | endif
  augroup END
]]

vim.cmd [[
  augroup MyConfig
    autocmd!
    " autocmd ColorScheme * hi clear DraculaBoundary
    " autocmd ColorScheme * hi DraculaBoundary ctermfg=61 guifg=#6272A4
    " autocmd ColorScheme * hi link FloatBorder TelescopeBorder
    " autocmd ColorScheme * hi link VertSplit DraculaBoundary

    autocmd FileType handlebars setlocal commentstring={{!--\ %s\ --}}
    autocmd BufRead,BufNewFile *.hbs set filetype=handlebars
    autocmd BufRead,BufNewFile jsconfig.json,jsconfig*.json,tsconfig.json,tsconfig*.json,*.json5 set filetype=jsonc

    autocmd BufWritePre *.go,*.js,*.ts,*.jsx,*.tsx lua vim.lsp.buf.formatting_seq_sync()

    autocmd BufWritePost *.lua PackerCompile

    autocmd BufWritePre,FileWritePre * silent! call mkdir(expand('<afile>:p:h'), 'p')
  augroup END
]]
