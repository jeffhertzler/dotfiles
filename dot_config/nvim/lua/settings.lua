-- don't load these built-in plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1

vim.g.mapleader = ' '
vim.g.tokyonight_dark_float = false

-- make sure neovim can find my node version when using volta
vim.g.node_host_prog = vim.fn.trim(vim.fn.system('volta which neovim-node-host'))

vim.opt.clipboard = 'unnamedplus'
vim.opt.completeopt = 'menu,menuone,noselect'
vim.opt.hidden = true
vim.opt.shortmess = vim.o.shortmess .. 'c'
vim.opt.showmode = false;
vim.opt.termguicolors = true
vim.opt.timeoutlen = 500

vim.opt.ignorecase = true
vim.opt.smartcase = true

-- do i really want to turn these off or can I just move where they live?
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

vim.opt.list = true
vim.opt.number = true
-- vim.wo.relativenumber = true
vim.opt.signcolumn = 'yes:1'
vim.opt.colorcolumn = ""

vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.tabstop = 2

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

    autocmd BufWritePre *.lua,*.php,*.go,*.js,*.ts,*.jsx,*.tsx lua vim.lsp.buf.formatting_seq_sync()

    autocmd BufWritePost *.lua PackerCompile

    autocmd BufWritePre,FileWritePre * silent! call mkdir(expand('<afile>:p:h'), 'p')
  augroup END
]]
