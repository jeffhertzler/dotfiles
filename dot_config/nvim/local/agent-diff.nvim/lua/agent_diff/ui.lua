local M = {}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_agent_diff_winbar(winbar)
  return type(winbar) == "string" and winbar:find("AgentDiffWinbarTitle", 1, true) ~= nil
end

local function escape(value)
  return tostring(value or ""):gsub("%%", "%%%%")
end

local function leader()
  local value = vim.g.mapleader or "\\"
  if value == " " then
    return "SPC"
  end
  return value
end

local function file_details(session)
  if session.files then
    local file = session.files[session.index]
    return file and file.path or "", string.format("%d/%d", session.index, #session.files)
  end
  return session.path or "", nil
end

local function revisions(session)
  return session.original_revision or session.revision or "HEAD", session.modified_revision or "WORKING"
end

local function value(session, role)
  local base, target = revisions(session)
  local path, position = file_details(session)
  local close = leader() .. (session.layout == "side-by-side" and " gD" or " gd")
  local title = role == "files" and " Agent Diff Files " or " Agent Diff "
  local details = role == "files"
      and string.format(" %s ", position or "")
    or string.format(
      " %s  %s → %s  %s%s ",
      session.layout == "side-by-side" and "side-by-side" or "inline",
      base,
      target,
      path,
      position and ("  " .. position) or ""
    )
  local hints = string.format("  %s close  %s b files", close, leader())
  if session.files and #session.files > 1 then
    hints = hints .. "  [f/]f navigate"
  end
  return table.concat({
    "%#AgentDiffWinbarTitle#",
    escape(title),
    "%#AgentDiffWinbar#",
    escape(details),
    "%=",
    "%#AgentDiffWinbarHint#",
    escape(hints .. " "),
  })
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "AgentDiffWinbar", { default = true, link = "WinBar" })
  vim.api.nvim_set_hl(0, "AgentDiffWinbarTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "AgentDiffWinbarHint", { default = true, link = "Comment" })
end

function M.setup()
  setup_highlights()
  local group = vim.api.nvim_create_augroup("AgentDiffHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = setup_highlights,
  })
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

local function role(session, win)
  if not session or not valid_win(win) then
    return nil
  end
  local bufnr = vim.api.nvim_win_get_buf(win)
  if win == session.modified_win and bufnr == session.modified_buf then
    return "modified"
  elseif win == session.original_win and bufnr == session.original_buf then
    return "original"
  elseif win == session.explorer_win and bufnr == session.explorer_buf then
    return "files"
  end
end

function M.update(session)
  for _, win in ipairs({ session.modified_win, session.original_win, session.explorer_win }) do
    local current_role = role(session, win)
    if current_role then
      vim.wo[win].winbar = value(session, current_role)
    end
  end
end

function M.sync()
  local ok, agent_diff = pcall(require, "agent_diff")
  local session = ok and agent_diff.get_session() or nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local current_role = role(session, win)
    if current_role then
      vim.wo[win].winbar = value(session, current_role)
    elseif is_agent_diff_winbar(vim.wo[win].winbar) then
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
