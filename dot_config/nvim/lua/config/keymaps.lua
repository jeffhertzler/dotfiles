-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>bs", "<cmd>so %<cr>", { desc = "Source" })
vim.keymap.set("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save" })
vim.keymap.set("n", "<leader>xn", function()
  vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next" })
vim.keymap.set("n", "<leader>xp", function()
  vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Prev" })
