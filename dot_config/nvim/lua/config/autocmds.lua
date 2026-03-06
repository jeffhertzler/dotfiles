-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

local tmux_nvim_group = vim.api.nvim_create_augroup("tmux-nvim-server", { clear = true })

local function publish_tmux_nvim_server()
  if vim.env.TMUX == nil or vim.env.TMUX == "" then
    return
  end

  if vim.env.TMUX_PANE == nil or vim.env.TMUX_PANE == "" then
    return
  end

  if vim.v.servername == nil or vim.v.servername == "" then
    return
  end

  vim.system(
    { "tmux", "set-option", "-wq", "-t", vim.env.TMUX_PANE, "@nvim_server", vim.v.servername },
    { detach = true }
  )
end

vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
  group = tmux_nvim_group,
  callback = publish_tmux_nvim_server,
})
