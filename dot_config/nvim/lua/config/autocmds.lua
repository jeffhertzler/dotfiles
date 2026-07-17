-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

local nvim_server_group = vim.api.nvim_create_augroup("nvim-server-publish", { clear = true })

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

local function herdr_nvim_server_path()
  if vim.env.HERDR_ENV ~= "1" or vim.env.HERDR_PANE_ID == nil or vim.env.HERDR_PANE_ID == "" then
    return nil, nil
  end

  local runtime_dir = vim.env.XDG_RUNTIME_DIR
  local registry_dir
  if runtime_dir ~= nil and runtime_dir ~= "" then
    registry_dir = runtime_dir .. "/herdr-nvim"
  else
    registry_dir = "/tmp/herdr-nvim-" .. vim.fn.getuid()
  end

  local pane_id = vim.env.HERDR_PANE_ID:gsub("[^%w_.:-]", "_")
  return registry_dir .. "/" .. pane_id .. ".server", registry_dir
end

local function publish_herdr_nvim_server()
  if vim.v.servername == nil or vim.v.servername == "" then
    return
  end

  local path, registry_dir = herdr_nvim_server_path()
  if path == nil then
    return
  end

  vim.fn.mkdir(registry_dir, "p", 448)
  vim.fn.writefile({ vim.v.servername }, path)
  vim.fn.setfperm(path, "rw-------")
end

local function remove_herdr_nvim_server()
  local path = herdr_nvim_server_path()
  if path == nil or vim.fn.filereadable(path) ~= 1 then
    return
  end

  local contents = vim.fn.readfile(path, "", 1)
  if contents[1] == vim.v.servername then
    vim.fn.delete(path)
  end
end

vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
  group = nvim_server_group,
  callback = function()
    publish_tmux_nvim_server()
    publish_herdr_nvim_server()
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = nvim_server_group,
  callback = remove_herdr_nvim_server,
})

-- LazyVim loads this file after VimEnter, so publish once immediately rather
-- than waiting for the terminal to emit its next FocusGained event.
vim.schedule(function()
  publish_tmux_nvim_server()
  publish_herdr_nvim_server()
end)
