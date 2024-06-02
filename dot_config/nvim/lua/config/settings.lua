vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- don't load these built-in plugins - which of these can lazy.nvim handle?
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0

local node20 = vim.fn.trim(vim.fn.system('volta run --node 20 which node'))
local nodeBin = node20:gsub('/node$', '')

local newPath = [[let $PATH = ']] .. nodeBin .. [[:' . $PATH]]
vim.cmd(newPath)

-- make sure neovim can find my node version when using volta
vim.g.node_host_prog = vim.fn.trim(vim.fn.system('volta which neovim-node-host'))
vim.g.python3_host_prog = vim.fn.trim(vim.fn.system('which python3'))

if require('config.utils').is_tmux() then
  vim.opt.tabline = " "
  vim.opt.showtabline = 2
end

vim.opt.clipboard = 'unnamedplus'
vim.opt.completeopt = 'menu,menuone,noselect'
vim.opt.hidden = true
vim.opt.shortmess = vim.o.shortmess .. 'c'
vim.opt.showmode = false;
vim.opt.termguicolors = true
vim.opt.timeoutlen = 500

vim.opt.scrolloff = 5

vim.opt.ignorecase = true
vim.opt.smartcase = true

-- do i really want to turn these off or can I just move where they live?
vim.opt.backup = false
vim.opt.swapfile = false
vim.opt.undofile = false
vim.opt.writebackup = false

vim.opt.list = true
vim.opt.number = true
-- vim.wo.relativenumber = true
vim.opt.signcolumn = 'yes:1'
vim.opt.colorcolumn = ""

-- vim.opt.formatoptions -- look into changing this (comments, markdown stuff I don't like)
vim.opt.autoindent = true
vim.opt.expandtab = true
vim.opt.shiftround = true
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.tabstop = 2

-- I don't use grep in this way so need to experiment with this
vim.opt.grepprg = 'rg --vimgrep'
vim.opt.grepformat = '%f:%l:%c:%m'

vim.filetype.add({
  pattern = {
    -- ['.mdx'] = 'mdx',
    ['.ember-cli'] = 'jsonc',
    ['.snyk'] = 'yaml',
    ['*.hbs'] = 'handlebars',
    ['*.json5'] = 'json5',
    ['*.jsonc'] = 'jsonc',
    ['jsconfig.json'] = 'jsonc',
    ['jsconfig*.json'] = 'jsonc',
    ['tsconfig.json'] = 'jsonc',
    ['tsconfig*.json'] = 'jsonc',
  },
})

-- vim.treesitter.language.register('markdown', 'mdx')
