local M = {}

local target_util = require("agent_review.target")

local function lifecycle()
  local ok, module = pcall(require, "codediff.ui.lifecycle")
  return ok and module or nil
end

local function counts(change)
  return change.original.end_line - change.original.start_line,
    change.modified.end_line - change.modified.start_line
end

function M.old_line_descriptor(diff_result, old_line, modified_line_count)
  if not diff_result or not diff_result.changes then
    return nil
  end

  local delta = 0
  for _, change in ipairs(diff_result.changes) do
    local original_count, modified_count = counts(change)
    if old_line < change.original.start_line then
      break
    end
    if old_line < change.original.end_line then
      local anchor_row
      if modified_count > 0 then
        anchor_row = change.modified.start_line - 1
      else
        anchor_row = math.min(change.modified.start_line - 1, modified_line_count - 1)
        anchor_row = math.max(anchor_row, 0)
      end
      return {
        row = anchor_row,
        above = true,
        change = change,
      }
    end
    delta = change.modified.end_line - change.original.end_line
  end

  local modified_line = old_line + delta
  return {
    row = math.max(0, math.min(modified_line - 1, modified_line_count - 1)),
    above = false,
  }
end

function M.old_lines_at_cursor(tabpage, cursor_line)
  local api = lifecycle()
  local session = api and api.get_session(tabpage) or nil
  if not session or api.get_layout(tabpage) ~= "inline" or not session.stored_diff_result then
    return {}
  end

  local original_buf, modified_buf = api.get_buffers(tabpage)
  if not (original_buf and modified_buf) then
    return {}
  end
  local modified_count = vim.api.nvim_buf_line_count(modified_buf)
  local result = {}

  for _, change in ipairs(session.stored_diff_result.changes or {}) do
    local original_count, modified_change_count = counts(change)
    if original_count > 0 then
      local anchor_line = math.max(1, math.min(change.modified.start_line, modified_count))
      local in_modified = modified_change_count > 0
        and cursor_line >= change.modified.start_line
        and cursor_line < change.modified.end_line
      if cursor_line == anchor_line or in_modified then
        for line = change.original.start_line, change.original.end_line - 1 do
          local text = vim.api.nvim_buf_get_lines(original_buf, line - 1, line, false)[1] or ""
          table.insert(result, { line = line, text = text, change = change })
        end
      end
    end
  end
  return result
end

function M.capture_old_line(tabpage, line)
  local api = lifecycle()
  local session = api and api.get_session(tabpage) or nil
  if not session or api.get_layout(tabpage) ~= "inline" then
    return nil, "not in an inline CodeDiff session"
  end
  local original_buf = api.get_buffers(tabpage)
  if not original_buf or not vim.api.nvim_buf_is_valid(original_buf) then
    return nil, "CodeDiff original buffer is unavailable"
  end
  if line < 1 or line > vim.api.nvim_buf_line_count(original_buf) then
    return nil, "old line is outside the original buffer"
  end

  local context = target_util.context_for_buffer(original_buf)
  if not context or not context.path then
    return nil, "could not determine the original file"
  end
  local target = {
    file = context.path,
    side = "old",
    start_line = line,
    end_line = line,
    selection = "line",
    column_encoding = "utf-8-byte",
  }
  return {
    tabpage = tabpage,
    bufnr = original_buf,
    host = "codediff",
    root = context.root,
    revision = {
      backend = context.backend,
      base_expression = context.base_revision,
      target_expression = context.target_revision,
      selected_expression = context.selected_revision,
    },
    target = target,
    anchor = target_util.anchor_for_buffer(original_buf, target),
  }
end

return M
