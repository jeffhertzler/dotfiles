-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local keymap_helpers = require("config.keymap_helpers")
local LazyRoot = require("lazyvim.util.root")

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

vim.keymap.set("n", "<leader>fe", function()
  local env_file = LazyRoot.get() .. "/.env"
  if vim.uv.fs_stat(env_file) then
    vim.cmd.edit(vim.fn.fnameescape(env_file))
    return
  end

  vim.notify("No root .env file found", vim.log.levels.WARN)
end, { desc = "Open Root .env" })

vim.keymap.set("n", "<leader>fh", function()
  Snacks.image.hover()
end, { desc = "Image Hover" })

vim.keymap.set("n", "<leader>ghj", function()
  require("gitsigns").nav_hunk("next")
end, { desc = "Next" })
vim.keymap.set("n", "<leader>ghk", function()
  require("gitsigns").nav_hunk("prev")
end, { desc = "Prev" })
vim.keymap.set("n", "<leader>ghJ", function()
  require("gitsigns").nav_hunk("next", { target = "all" })
end, { desc = "Next All" })
vim.keymap.set("n", "<leader>ghK", function()
  require("gitsigns").nav_hunk("prev", { target = "all" })
end, { desc = "Prev All" })
