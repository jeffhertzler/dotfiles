local M = {}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_agent_diff_winbar(winbar)
  return type(winbar) == "string" and winbar:find("AgentDiffWinbarTitle", 1, true) ~= nil
end

function M.setup()
  pcall(vim.api.nvim_del_augroup_by_name, "AgentDiffHighlights")
  local group = vim.api.nvim_create_augroup("AgentDiffUI", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function()
      vim.schedule(M.sync)
    end,
  })
  vim.schedule(M.sync)
end

function M.capture(session, win)
  if not valid_win(win) then
    return
  end
  session.saved_winbars = session.saved_winbars or {}
  if session.saved_winbars[win] == nil then
    local winbar = vim.wo[win].winbar
    session.saved_winbars[win] = is_agent_diff_winbar(winbar) and "" or winbar
  end
end

function M.update()
  M.sync()
end

function M.sync()
  local ok, agent_diff = pcall(require, "agent_diff")
  local session = ok and agent_diff.get_session() or nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_agent_diff_winbar(vim.wo[win].winbar) then
      vim.wo[win].winbar = (session and session.saved_winbars and session.saved_winbars[win]) or ""
    end
  end
end

function M.restore(session)
  for win, winbar in pairs(session.saved_winbars or {}) do
    if valid_win(win) then
      vim.wo[win].winbar = winbar
    end
  end
end

return M
