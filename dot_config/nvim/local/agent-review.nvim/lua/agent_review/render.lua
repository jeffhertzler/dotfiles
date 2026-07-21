local M = {}

local state = require("agent_review.state")
local target_util = require("agent_review.target")

local anchor_ns = vim.api.nvim_create_namespace("agent_review_anchor")
local render_ns = vim.api.nvim_create_namespace("agent_review_render")

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function line_text(bufnr, line)
  return vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
end

local function clamped_target(bufnr, source)
  local target = vim.deepcopy(source)
  local line_count = math.max(1, vim.api.nvim_buf_line_count(bufnr))
  target.start_line = math.min(math.max(1, target.start_line), line_count)
  target.end_line = math.min(math.max(target.start_line, target.end_line), line_count)
  if target.start_col then
    target.start_col = math.min(math.max(1, target.start_col), #line_text(bufnr, target.start_line) + 1)
    target.end_col = math.min(math.max(1, target.end_col), #line_text(bufnr, target.end_line) + 1)
  end
  return target
end

local function sync_anchor(annotation)
  if annotation.freshness == "stale" then
    return
  end
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
  if annotation.target.selection == "character" then
    annotation.target.end_line = (details.end_row or position[1]) + 1
    annotation.target.start_col = position[2] + 1
    annotation.target.end_col =
      target_util.previous_char_col(runtime.bufnr, details.end_row or position[1], details.end_col or position[2])
  else
    annotation.target.end_line = annotation.target.start_line + (runtime.line_span or 0)
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

  local freshness, reanchored = require("agent_review.reanchor").resolve(bufnr, annotation)
  local changed = annotation.freshness ~= freshness
  if reanchored then
    annotation.target.start_line = reanchored.start_line
    annotation.target.start_col = reanchored.start_col
    annotation.target.end_line = reanchored.end_line
    annotation.target.end_col = reanchored.end_col
    annotation.target.selection = reanchored.selection
    changed = true
  end
  annotation.freshness = freshness
  if changed then
    annotation.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    state.changed()
  end

  local target = clamped_target(bufnr, annotation.target)
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
  annotation._runtime = {
    bufnr = bufnr,
    mark_id = mark_id,
    line_span = target.end_line - target.start_line,
  }
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
    return "AgentReviewResolved", "AgentReviewResolvedRange", "AgentReviewResolvedLine"
  end
  if annotation.freshness == "stale" then
    return "AgentReviewStale", "AgentReviewStaleRange", "AgentReviewStaleLine"
  end
  if annotation.author and annotation.author.kind == "agent" then
    return "AgentReviewAgent", "AgentReviewAgentRange", "AgentReviewAgentLine"
  end
  return "AgentReviewNote", "AgentReviewRange", "AgentReviewLine"
end

local function comment_box(annotation, highlight)
  local author = annotation.author or { kind = "human" }
  local author_name = author.kind == "agent" and ("AGENT " .. (author.name or "agent")) or "HUMAN"
  local state_labels = {}
  if annotation.status and annotation.status ~= "open" then
    table.insert(state_labels, string.upper(annotation.status))
  end
  if annotation.freshness and annotation.freshness ~= "fresh" then
    table.insert(state_labels, string.upper(annotation.freshness))
  end
  local states = #state_labels > 0 and (" · " .. table.concat(state_labels, " · ")) or ""
  local header = string.format(
    "[%s %s%s · %s]",
    author_name,
    string.upper(annotation.kind or "note"),
    states,
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
  local target = clamped_target(bufnr, annotation.target)
  local note_highlight, range_highlight, line_highlight = annotation_highlights(annotation)

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
  if annotation.session_id then
    local active = require("agent_review.sessions").current(require("agent_review.scope").for_annotation(annotation))
    if not active or active.id ~= annotation.session_id then
      return false
    end
  end
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

local function render_inline_old(tabpage, original_buf, modified_buf)
  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(tabpage)
  if not session or lifecycle.get_layout(tabpage) ~= "inline" or not session.stored_diff_result then
    return
  end
  if not (valid_buffer(original_buf) and valid_buffer(modified_buf)) then
    return
  end

  local original_context = target_util.context_for_buffer(original_buf)
  if not original_context then
    return
  end
  local modified_line_count = vim.api.nvim_buf_line_count(modified_buf)
  local adapter = require("agent_review.codediff")

  for _, annotation in ipairs(state.list()) do
    if matches_context(annotation, original_context) then
      ensure_anchor(annotation, original_buf)
      sync_anchor(annotation)
      local descriptor = adapter.old_line_descriptor(
        session.stored_diff_result,
        annotation.target.end_line,
        modified_line_count
      )
      if descriptor then
        local note_highlight = annotation_highlights(annotation)
        pcall(vim.api.nvim_buf_set_extmark, modified_buf, render_ns, descriptor.row, 0, {
          sign_text = "~",
          sign_hl_group = note_highlight,
          virt_lines = comment_box(annotation, note_highlight),
          virt_lines_above = descriptor.above,
          virt_lines_overflow = "scroll",
          priority = 240,
        })
      end
    end
  end
end

function M.revalidate_buffer(bufnr)
  if not valid_buffer(bufnr) then
    return
  end
  local context = target_util.context_for_buffer(bufnr)
  if not context then
    return
  end

  for _, annotation in ipairs(state.list()) do
    if matches_context(annotation, context) then
      sync_anchor(annotation)
      local runtime = annotation._runtime
      if runtime and valid_buffer(runtime.bufnr) then
        pcall(vim.api.nvim_buf_del_extmark, runtime.bufnr, anchor_ns, runtime.mark_id)
      end
      annotation._runtime = nil
    end
  end
  M.refresh_buffer(bufnr)
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

  if context.host == "codediff" and context.view_side == "new" then
    local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
    local tabpage = ok and lifecycle.find_tabpage_by_buffer(bufnr) or nil
    if tabpage and lifecycle.get_layout(tabpage) == "inline" then
      local original_buf, modified_buf = lifecycle.get_buffers(tabpage)
      render_inline_old(tabpage, original_buf, modified_buf)
    end
  end
end

function M.sync()
  for _, annotation in ipairs(state.list()) do
    sync_anchor(annotation)
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
  vim.api.nvim_set_hl(0, "AgentReviewNote", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "AgentReviewRange", { default = true, link = "Visual" })
  vim.api.nvim_set_hl(0, "AgentReviewLine", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "AgentReviewAgent", { default = true, link = "DiagnosticHint" })
  vim.api.nvim_set_hl(0, "AgentReviewAgentRange", { default = true, link = "Search" })
  vim.api.nvim_set_hl(0, "AgentReviewAgentLine", { default = true, link = "DiffChange" })
  vim.api.nvim_set_hl(0, "AgentReviewResolved", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "AgentReviewResolvedRange", { default = true, link = "IncSearch" })
  vim.api.nvim_set_hl(0, "AgentReviewResolvedLine", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "AgentReviewStale", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "AgentReviewStaleRange", { default = true, link = "WarningMsg" })
  vim.api.nvim_set_hl(0, "AgentReviewStaleLine", { default = true, link = "DiffDelete" })
end

return M
