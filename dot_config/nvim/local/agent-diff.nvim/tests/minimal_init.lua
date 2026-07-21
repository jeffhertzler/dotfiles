local root = assert(vim.env.AGENT_DIFF_PLUGIN_ROOT)
local data = vim.fn.stdpath("data") .. "/lazy"
vim.opt.runtimepath:prepend(root)
for _, dependency in ipairs({ "codediff.nvim", "gitsigns.nvim", "neogit", "plenary.nvim", "snacks.nvim" }) do
  local path = data .. "/" .. dependency
  if vim.uv.fs_stat(path) then
    vim.opt.runtimepath:prepend(path)
  end
end
vim.g.mapleader = " "
require("agent_diff").setup({ initial_timeout_ms = 100, live_timeout_ms = 50, debounce_ms = 10 })
