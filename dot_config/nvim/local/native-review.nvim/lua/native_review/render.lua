local M = {}

local state = require("native_review.state")
local target_util = require("native_review.target")

local anchor_ns = vim.api.nvim_create_namespace("native_review_anchor")
local render_ns = vim.api.nvim_create_namespace("native_review_render")

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function line_text(bufnr, line)
  return vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
end

local function clamp_target(bufnr, target)
  local line_count = math.max(1, vim.api.nvim_buf_line_count(bufnr))
  target.start_line = math.min(math.max(1, target.start_line), line_count)
  target.end_line = math.min(math.max(target.start_line, target.end_line), line_count)
  if target.start_col then
    target.start_col = math.min(math.max(1, target.start_col), #line_text(bufnr, target.start_line) + 1)
    target.end_col = math.min(math.max(1, target.end_col), #line_text(bufnr, target.end_line) + 1)
  end
end

local function sync_anchor(annotation)
  local runtime = annotation._runtime
  if not runtime or not valid_buffer(runtime.bufnr) then
    annotation._runtime = nil
    return
  end

  local position = vim.api.nvim_buf_get_extmark_by_id(runtime.bufnr, anchor_ns, runtime.mark_id, { details = true })
  if #position == 0 then
    annotation._runtime = nil
    return
  end

  local details = position[3] or {}
  annotation.target.start_line = position[1] + 1
  annotation.target.end_line = (details.end_row or position[1]) + 1
  if annotation.target.selection == "character" then
    annotation.target.start_col = position[2] + 1
    annotation.target.end_col =
      target_util.previous_char_col(runtime.bufnr, details.end_row or position[1], details.end_col or position[2])
  end
end

local function ensure_anchor(annotation, bufnr)
  local runtime = annotation._runtime
  if runtime and runtime.bufnr == bufnr and valid_buffer(bufnr) then
    local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, anchor_ns, runtime.mark_id, {})
    if #position > 0 then
      return
    end
  end

  sync_anchor(annotation)
  runtime = annotation._runtime
  if runtime and valid_buffer(runtime.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, runtime.bufnr, anchor_ns, runtime.mark_id)
  end

  local target = annotation.target
  clamp_target(bufnr, target)
  local start_row = target.start_line - 1
  local start_col = target.start_col and target.start_col - 1 or 0
  local end_row = target.end_line - 1
  local end_col = target_util.end_col_exclusive(bufnr, target)
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, anchor_ns, start_row, start_col, {
    end_row = end_row,
    end_col = end_col,
    right_gravity = false,
    end_right_gravity = true,
    invalidate = false,
  })
  annotation._runtime = { bufnr = bufnr, mark_id = mark_id }
end

local function wrapped_lines(text, width)
  local result = {}
  for _, source_line in ipairs(vim.split(text, "\n", { plain = true })) do
    if source_line == "" then
      table.insert(result, "")
    else
      local remaining = source_line
      while vim.fn.strdisplaywidth(remaining) > width do
        local split_at = width
        while split_at > 1 and remaining:sub(split_at, split_at) ~= " " do
          split_at = split_at - 1
        end
        if split_at == 1 then
          split_at = width
        end
        table.insert(result, vim.trim(remaining:sub(1, split_at)))
        remaining = vim.trim(remaining:sub(split_at + 1))
      end
      table.insert(result, remaining)
    end
  end
  return result
end

local function location(target)
  local side_names = { old = "OLD", new = "NEW", working = "WORKING" }
  local side = side_names[target.side] or string.upper(target.side or "FILE")
  local start = tostring(target.start_line)
  local finish = tostring(target.end_line)
  if target.start_col then
    start = string.format("%d:%d", target.start_line, target.start_col)
    finish = string.format("%d:%d", target.end_line, target.end_col)
  end
  local range = start == finish and start or start .. "–" .. finish
  return string.format("%s %s", side, range)
end

local function annotation_highlights(annotation)
  if annotation.status == "resolved" then
    return "NativeReviewResolved", "NativeReviewResolvedRange", "NativeReviewResolvedLine"
  end
  if annotation.author and annotation.author.kind == "agent" then
    return "NativeReviewAgent", "NativeReviewAgentRange", "NativeReviewAgentLine"
  end
  return "NativeReviewNote", "NativeReviewRange", "NativeReviewLine"
end

local function comment_box(annotation, highlight)
  local author = annotation.author or { kind = "human" }
  local author_name = author.kind == "agent" and ("AGENT " .. (author.name or "agent")) or "HUMAN"
  local status = annotation.status and annotation.status ~= "open" and (" · " .. string.upper(annotation.status)) or ""
  local header = string.format(
    "[%s %s%s · %s]",
    author_name,
    string.upper(annotation.kind or "note"),
    status,
    location(annotation.target)
  )
  local lines = wrapped_lines(annotation.body, 72)
  local content_width = vim.fn.strdisplaywidth(header)
  for _, text in ipairs(lines) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(text))
  end
  content_width = math.max(content_width, 24)

  local virtual_lines = {
    {
      {
        "╭─" .. header .. string.rep("─", content_width - vim.fn.strdisplaywidth(header) + 1) .. "╮",
        highlight,
      },
    },
  }
  for _, text in ipairs(lines) do
    local padding = content_width - vim.fn.strdisplaywidth(text)
    table.insert(virtual_lines, { { "│ " .. text .. string.rep(" ", padding) .. " │", highlight } })
  end
  table.insert(virtual_lines, { { "╰" .. string.rep("─", content_width + 2) .. "╯", highlight } })
  return virtual_lines
end

local function render_range(bufnr, annotation)
  local target = annotation.target
  local note_highlight, range_highlight, line_highlight = annotation_highlights(annotation)
  clamp_target(bufnr, target)

  if target.selection == "character" then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, render_ns, target.start_line - 1, target.start_col - 1, {
      end_row = target.end_line - 1,
      end_col = target_util.end_col_exclusive(bufnr, target),
      hl_group = range_highlight,
      priority = 220,
    })
  else
    for line = target.start_line, target.end_line do
      pcall(vim.api.nvim_buf_set_extmark, bufnr, render_ns, line - 1, 0, {
        line_hl_group = line_highlight,
        priority = 220,
      })
    end
  end

  pcall(vim.api.nvim_buf_set_extmark, bufnr, render_ns, target.start_line - 1, 0, {
    sign_text = "●",
    sign_hl_group = note_highlight,
    priority = 230,
  })
  pcall(vim.api.nvim_buf_set_extmark, bufnr, render_ns, target.end_line - 1, 0, {
    virt_lines = comment_box(annotation, note_highlight),
    virt_lines_above = false,
    virt_lines_overflow = "scroll",
    priority = 230,
  })
end

local function same_root(first, second)
  return (first or "") == (second or "")
end

local function matches_context(annotation, context)
  if not same_root(annotation.root, context.root) then
    return false
  end
  if annotation.target.file ~= context.path or annotation.target.side ~= context.side then
    return false
  end
  if context.side == "working" then
    return true
  end
  return annotation.revision.selected_expression == context.selected_revision
end

function M.refresh_buffer(bufnr)
  if not valid_buffer(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, render_ns, 0, -1)
  local context = target_util.context_for_buffer(bufnr)
  if not context or not context.path then
    return
  end

  for _, annotation in ipairs(state.list()) do
    if matches_context(annotation, context) then
      ensure_anchor(annotation, bufnr)
      sync_anchor(annotation)
      render_range(bufnr, annotation)
    end
  end
end

function M.refresh_visible()
  local seen = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if not seen[bufnr] then
        seen[bufnr] = true
        M.refresh_buffer(bufnr)
      end
    end
  end
end

function M.refresh(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  for _, annotation in ipairs(state.list()) do
    sync_anchor(annotation)
  end

  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  local session = ok and lifecycle.get_session(tabpage) or nil
  if not session then
    M.refresh_buffer(vim.api.nvim_get_current_buf())
    return
  end

  local original_buf, modified_buf = lifecycle.get_buffers(tabpage)
  if lifecycle.get_layout(tabpage) == "side-by-side" then
    M.refresh_buffer(original_buf)
  elseif valid_buffer(original_buf) then
    vim.api.nvim_buf_clear_namespace(original_buf, render_ns, 0, -1)
  end
  M.refresh_buffer(modified_buf)
end

function M.refresh_annotation(annotation)
  local runtime = annotation and annotation._runtime
  if runtime and valid_buffer(runtime.bufnr) then
    M.refresh_buffer(runtime.bufnr)
  else
    M.refresh()
  end
end

function M.remove(annotation)
  local runtime = annotation and annotation._runtime
  local bufnr = runtime and runtime.bufnr or nil
  if runtime and valid_buffer(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, anchor_ns, runtime.mark_id)
  end
  if annotation then
    annotation._runtime = nil
  end
  if valid_buffer(bufnr) then
    M.refresh_buffer(bufnr)
  else
    M.refresh()
  end
end

function M.clear_all()
  for _, annotation in ipairs(state.list()) do
    local runtime = annotation._runtime
    if runtime and valid_buffer(runtime.bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, runtime.bufnr, anchor_ns, runtime.mark_id)
    end
    annotation._runtime = nil
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if valid_buffer(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, render_ns, 0, -1)
      vim.api.nvim_buf_clear_namespace(bufnr, anchor_ns, 0, -1)
    end
  end
end

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "NativeReviewNote", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "NativeReviewRange", { default = true, link = "Visual" })
  vim.api.nvim_set_hl(0, "NativeReviewLine", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "NativeReviewAgent", { default = true, link = "DiagnosticHint" })
  vim.api.nvim_set_hl(0, "NativeReviewAgentRange", { default = true, link = "Search" })
  vim.api.nvim_set_hl(0, "NativeReviewAgentLine", { default = true, link = "DiffChange" })
  vim.api.nvim_set_hl(0, "NativeReviewResolved", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "NativeReviewResolvedRange", { default = true, link = "IncSearch" })
  vim.api.nvim_set_hl(0, "NativeReviewResolvedLine", { default = true, link = "CursorLine" })
end

return M
