vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.g.lazyvim_php_lsp = "intelephense"

vim.g.snacks_animate = false

local node22 = vim.fn.trim(vim.fn.system("volta run --node 22 which node"))
local nodeBin = node22:gsub("/node$", "")

local newPath = [[let $PATH = ']] .. nodeBin .. [[:' . $PATH]]
vim.cmd(newPath)

vim.g.node_host_prog = vim.fn.trim(vim.fn.system("volta which neovim-node-host"))

vim.opt.relativenumber = false
vim.opt.showtabline = 0
vim.opt.swapfile = false

vim.opt.clipboard = { "unnamed", "unnamedplus" }

vim.filetype.add({
  pattern = {
    [".ember-cli"] = "jsonc",
    -- ["*.hbs"] = "handlebars",
  },
})
