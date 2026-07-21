local M = {}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
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
end

function M.capture(session, win)
  if not valid_win(win) then
    return
  end
  session.saved_winbars = session.saved_winbars or {}
  if session.saved_winbars[win] == nil then
    session.saved_winbars[win] = vim.wo[win].winbar
  end
end

function M.update(session)
  if valid_win(session.modified_win) then
    vim.wo[session.modified_win].winbar = value(session, "modified")
  end
  if valid_win(session.original_win) then
    vim.wo[session.original_win].winbar = value(session, "original")
  end
  if valid_win(session.explorer_win) then
    vim.wo[session.explorer_win].winbar = value(session, "files")
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
