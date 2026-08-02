local root = assert(vim.env.AGENT_BRIDGE_PLUGIN_ROOT, "AGENT_BRIDGE_PLUGIN_ROOT is required")
local data = vim.fn.stdpath("data") .. "/lazy"

vim.opt.runtimepath:prepend(root)
local snacks = data .. "/snacks.nvim"
if vim.uv.fs_stat(snacks) then
  vim.opt.runtimepath:prepend(snacks)
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
