local M = {}

local target_util = require("agent_review.target")
local mapping = require("agent_review.codediff")

local function session()
  local ok, agent_diff = pcall(require, "agent_diff")
  return ok and agent_diff.get_session() or nil
end

M.old_line_descriptor = mapping.old_line_descriptor

function M.old_lines_at_cursor(cursor_line)
  local current = session()
  if not current or current.layout ~= "inline" or not current.diff_result then
    return {}
  end
  local modified_count = vim.api.nvim_buf_line_count(current.modified_buf)
  local result = {}
  for _, change in ipairs(current.diff_result.changes or {}) do
    local original_count = change.original.end_line - change.original.start_line
    local modified_count_in_change = change.modified.end_line - change.modified.start_line
    if original_count > 0 then
      local anchor_line = math.max(1, math.min(change.modified.start_line, modified_count))
      local in_modified = modified_count_in_change > 0
        and cursor_line >= change.modified.start_line
        and cursor_line < change.modified.end_line
      if cursor_line == anchor_line or in_modified then
        for line = change.original.start_line, change.original.end_line - 1 do
          local text = vim.api.nvim_buf_get_lines(current.original_buf, line - 1, line, false)[1] or ""
          table.insert(result, { line = line, text = text, change = change })
        end
      end
    end
  end
  return result
end

function M.capture_old_line(line)
  local current = session()
  if not current or current.layout ~= "inline" then
    return nil, "not in an inline Agent Diff session"
  end
  if line < 1 or line > vim.api.nvim_buf_line_count(current.original_buf) then
    return nil, "old line is outside the original buffer"
  end
  local context = target_util.context_for_buffer(current.original_buf)
  if not context then
    return nil, "could not determine the original file"
  end
  local annotation_target = {
    file = context.path,
    side = "old",
    start_line = line,
    end_line = line,
    selection = "line",
    column_encoding = "utf-8-byte",
  }
  return {
    tabpage = context.tabpage,
    bufnr = current.original_buf,
    host = "agent_diff",
    root = context.root,
    revision = {
      backend = context.backend,
      base_expression = context.base_revision,
      target_expression = context.target_revision,
      selected_expression = context.selected_revision,
    },
    target = annotation_target,
    anchor = target_util.anchor_for_buffer(current.original_buf, annotation_target),
  }
end

return M
