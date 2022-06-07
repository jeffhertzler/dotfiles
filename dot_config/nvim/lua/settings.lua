-- don't load these built-in plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1

vim.g.mapleader = ' '
-- vim.g.tokyonight_dark_float = false

-- make sure neovim can find my node version when using volta
vim.g.node_host_prog = vim.fn.trim(vim.fn.system('volta which neovim-node-host'))

if require('helpers').is_tmux() then
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
vim.cmd [[colorscheme catppuccin]]

local configGroup = vim.api.nvim_create_augroup("MyConfig", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  command = [[if v:event.operator is 'y' && v:event.regname is '' | OSCYankReg + | endif]],
  group = configGroup,
})
vim.api.nvim_create_autocmd("TextYankPost", {
  command = [[silent! lua vim.highlight.on_yank()]],
  group = configGroup,
})
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.hbs",
  command = [[set filetype=handlebars]],
  group = configGroup,
})
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "jsconfig.json", "jsconfig*.json", "tsconfig*.json", "*.json5" },
  command = [[set filetype=json5]],
  group = configGroup,
})
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.lua", "*.php", "*.go", "*.json", "*.js", "*.ts", "*.jsx", "*.tsx" },
  callback = function() require("plugins.lsp").format() end,
  group = configGroup,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "plugins.lua",
  command = [[PackerCompile]],
  group = configGroup,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "handlebars",
  command = [[setlocal commentstring={{!--\ %s\ --}}]],
  group = configGroup,
})
vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
  callback = function() require("nvim-lightbulb").update_lightbulb() end,
  group = configGroup,
})
vim.api.nvim_create_autocmd({ "BufWritePre", "FileWritePre" }, {
  command = [[silent! call mkdir(expand('<afile>:p:h'), 'p')]],
  group = configGroup,
})
