-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local keymap_helpers = require("config.keymap_helpers")

vim.keymap.set("n", "<leader>bs", "<cmd>so %<cr>", { desc = "Source" })
vim.keymap.set("n", "<leader>fs", "<cmd>w<cr>", { desc = "Save" })

vim.keymap.set("n", "<leader>xn", function()
  vim.diagnostic.jump({ count = 1, float = true, severity = { min = vim.diagnostic.severity.WARN } })
end, { desc = "Next" })

vim.keymap.set("n", "<leader>xp", function()
  vim.diagnostic.jump({ count = -1, float = true, severity = { min = vim.diagnostic.severity.WARN } })
end, { desc = "Prev" })

vim.keymap.set("n", "<leader>ff", function()
  return keymap_helpers.pick_with_ignored_allowlist("files", "files")
end, { desc = "Find Files" })
vim.keymap.set("n", "<leader>fF", function()
  return keymap_helpers.pick_with_ignored_allowlist("files", "files", { cwd = keymap_helpers.get_current_dir() })
end, { desc = "Find Files (Current)" })

vim.keymap.set("n", "<leader>sg", function()
  return keymap_helpers.pick_with_ignored_allowlist("live_grep", "grep")
end, { desc = "Grep" })
vim.keymap.set("n", "<leader>sG", function()
  return keymap_helpers.pick_with_ignored_allowlist("live_grep", "grep", { cwd = keymap_helpers.get_current_dir() })
end, { desc = "Grep (Current)" })

vim.keymap.set({ "n", "x" }, "<leader>sW", function()
  return keymap_helpers.pick_with_ignored_allowlist(
    "grep_word",
    "grep_word",
    { cwd = keymap_helpers.get_current_dir() }
  )
end, { desc = "Visual selection or word (Current)" })

vim.keymap.set("n", "<leader>fh", function()
  Snacks.image.hover()
end, { desc = "Image Hover" })
