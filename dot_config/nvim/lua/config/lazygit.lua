local M = {}

---Close the terminal hosting LazyGit after its editor subprocess returns.
---@param bufnr integer
function M.close_terminal(bufnr)
  local function quit_lazygit()
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "terminal" then
      return
    end

    local channel = vim.bo[bufnr].channel
    if channel > 0 then
      pcall(vim.api.nvim_chan_send, channel, "q")
    end
  end

  vim.defer_fn(quit_lazygit, 100)
  vim.defer_fn(quit_lazygit, 250)
  return true
end

return M
