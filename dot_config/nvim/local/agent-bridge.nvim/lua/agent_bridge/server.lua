local M = {}

local initialized = false

local function registry_path()
  if vim.env.HERDR_ENV ~= "1" or not vim.env.HERDR_PANE_ID or vim.env.HERDR_PANE_ID == "" then
    return nil, nil
  end
  local directory = (vim.env.XDG_RUNTIME_DIR and vim.env.XDG_RUNTIME_DIR ~= "")
      and (vim.env.XDG_RUNTIME_DIR .. "/herdr-nvim")
    or ("/tmp/herdr-nvim-" .. vim.fn.getuid())
  local pane = vim.env.HERDR_PANE_ID:gsub("[^%w_.:-]", "_")
  return directory .. "/" .. pane .. ".server", directory
end

function M.publish()
  if not vim.v.servername or vim.v.servername == "" then
    return
  end

  if vim.env.TMUX and vim.env.TMUX ~= "" and vim.env.TMUX_PANE and vim.env.TMUX_PANE ~= "" then
    vim.system({ "tmux", "set-option", "-wq", "-t", vim.env.TMUX_PANE, "@nvim_server", vim.v.servername }, { detach = true })
  end

  local path, directory = registry_path()
  if path then
    vim.fn.mkdir(directory, "p")
    vim.fn.writefile({ vim.v.servername }, path)
    vim.fn.setfperm(path, "rw-------")
  end
end

function M.remove()
  local path = registry_path()
  if not path or vim.fn.filereadable(path) ~= 1 then
    return
  end
  local contents = vim.fn.readfile(path, "", 1)
  if contents[1] == vim.v.servername then
    vim.fn.delete(path)
  end
end

function M.setup()
  if initialized then
    return
  end
  initialized = true
  local group = vim.api.nvim_create_augroup("AgentBridgeServer", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
    group = group,
    callback = M.publish,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = M.remove,
  })
  vim.schedule(M.publish)
end

return M
