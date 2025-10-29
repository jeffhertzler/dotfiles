-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local get_current_dir = function()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.fn.expand("%:p:h")
  if vim.bo[buf].filetype == "oil" then
    path = path:gsub("^oil://", "")
  end
  return path
end

vim.keymap.set("n", "<leader>bs", "<cmd>so %<cr>", { desc = "Source" })
vim.keymap.set("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save" })

vim.keymap.set("n", "<leader>xn", function()
  vim.diagnostic.jump({ count = 1, float = true, severity = { min = vim.diagnostic.severity.WARN } })
end, { desc = "Next" })

vim.keymap.set("n", "<leader>xp", function()
  vim.diagnostic.jump({ count = -1, float = true, severity = { min = vim.diagnostic.severity.WARN } })
end, { desc = "Prev" })

vim.keymap.set("n", "<leader>fF", function()
  return LazyVim.pick("files", { cwd = get_current_dir() })()
end, { desc = "Find Files (Current)" })

vim.keymap.set("n", "<leader>sG", function()
  return LazyVim.pick("live_grep", { cwd = get_current_dir() })()
end, { desc = "Grep (Current)" })

vim.keymap.set({ "n", "x" }, "<leader>sW", function()
  return LazyVim.pick("grep_word", { cwd = get_current_dir() })()
end, { desc = "Visual selection or word (Current)" })
