local M = {}

local initialized = false

local function context()
  local target = require("agent_review.target")
  local current = target.context_for_buffer(vim.api.nvim_get_current_buf()) or target.current_context()
  if current and current.path then
    return current, require("agent_review.scope").key(current.root, current.path)
  end

  local cwd = vim.fn.getcwd(0)
  local root = vim.fs.root(cwd, { ".jj", ".git" })
  if root then
    root = vim.fs.normalize(root)
    return nil, require("agent_review.scope").key(root)
  end
end

function M.counts()
  local current, workspace = context()
  local counts = { current = 0, total = 0, stale = 0 }
  if not workspace then
    return counts
  end

  local sessions = require("agent_review.sessions")
  local session = sessions.current(workspace)
  if not session then
    return counts
  end

  for _, annotation in ipairs(sessions.annotations(session.id)) do
    if annotation.status ~= "resolved" then
      counts.total = counts.total + 1
      if annotation.freshness == "stale" then
        counts.stale = counts.stale + 1
      end
      if current and annotation.target and annotation.target.file == current.path then
        counts.current = counts.current + 1
      end
    end
  end
  counts.session = session.id
  return counts
end

function M.text()
  local counts = M.counts()
  if counts.total == 0 then
    return ""
  end
  return string.format("Review %d/%d", counts.current, counts.total)
end

function M.has()
  return M.counts().total > 0
end

function M.open()
  local counts = M.counts()
  if not counts.session then
    return
  end
  require("agent_review.picker").open({ session = counts.session })
end

function M.setup()
  if initialized then
    return
  end
  initialized = true
  require("agent_review.state").on_change(function()
    vim.schedule(function()
      pcall(vim.cmd, "redrawstatus")
    end)
  end)
end

return M
