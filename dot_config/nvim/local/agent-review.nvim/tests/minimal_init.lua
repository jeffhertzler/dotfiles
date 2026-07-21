local plugin_root = assert(vim.env.AGENT_REVIEW_PLUGIN_ROOT, "AGENT_REVIEW_PLUGIN_ROOT is required")
local data = vim.fn.stdpath("data") .. "/lazy"

vim.opt.runtimepath:prepend(plugin_root)
for _, dependency in ipairs({ "snacks.nvim", "codediff.nvim", "plenary.nvim" }) do
  local path = data .. "/" .. dependency
  if vim.uv.fs_stat(path) then
    vim.opt.runtimepath:prepend(path)
  end
end

local local_root = vim.fs.dirname(plugin_root)
local bridge_root = local_root .. "/agent-bridge.nvim"
if vim.uv.fs_stat(bridge_root) then
  vim.opt.runtimepath:prepend(bridge_root)
end
local diff_root = local_root .. "/agent-diff.nvim"
if vim.uv.fs_stat(diff_root) then
  vim.opt.runtimepath:prepend(diff_root)
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

require("agent_review").setup({
  persistence = {
    path = assert(vim.env.NVIM_AGENT_REVIEW_STATE, "NVIM_AGENT_REVIEW_STATE is required"),
    debounce_ms = 10,
  },
})
