local M = {}

local initialized = false
local ns = vim.api.nvim_create_namespace("agent_review_patch")

local function workspace()
  local ok, patch = pcall(require, "agent_diff.patch")
  return ok and patch.get() or nil
end

local function source(metadata)
  if not metadata or not metadata.hunk or not metadata.text then
    return nil
  end
  if metadata.section == "staged" then
    if metadata.kind == "delete" then
      return "old", "HEAD", metadata.old_line
    end
    return "new", "INDEX", metadata.new_line
  end
  if metadata.kind == "delete" then
    return "old", "INDEX", metadata.old_line
  end
  return "working", "WORKING", metadata.new_line
end

local function selected_metadata(current, opts)
  local first, last
  if opts.visual then
    first, last = vim.fn.getpos("v")[2], vim.fn.getpos(".")[2]
    if first > last then
      first, last = last, first
    end
  else
    first = vim.api.nvim_win_get_cursor(0)[1]
    last = first
  end

  local selected = {}
  for row = first, last do
    local metadata = current.rows[row]
    if metadata and metadata.text and (metadata.kind == "delete" or metadata.kind == "add" or metadata.kind == "context") then
      table.insert(selected, { row = row, metadata = metadata })
    end
  end
  if #selected == 0 then
    return nil, "Place the cursor on a patch content line"
  end

  local side, revision, start_line = source(selected[1].metadata)
  local end_line = start_line
  for _, item in ipairs(selected) do
    local item_side, item_revision, line = source(item.metadata)
    if item_side ~= side or item_revision ~= revision then
      return nil, "Review selection cannot cross patch sides or sections"
    end
    start_line, end_line = math.min(start_line, line), math.max(end_line, line)
  end
  return selected, side, revision, start_line, end_line
end

local function anchor(current, side, revision, start_line, end_line, selected)
  local by_line = {}
  for _, metadata in pairs(current.rows) do
    local item_side, item_revision, line = source(metadata)
    if item_side == side and item_revision == revision and line then
      by_line[line] = metadata.text
    end
  end
  local before, after, body = {}, {}, {}
  for line = math.max(1, start_line - 3), start_line - 1 do
    if by_line[line] then
      table.insert(before, by_line[line])
    end
  end
  for _, item in ipairs(selected) do
    table.insert(body, item.metadata.text)
  end
  for line = end_line + 1, end_line + 3 do
    if by_line[line] then
      table.insert(after, by_line[line])
    end
  end
  return { before = before, selected = body, after = after }
end

function M.capture(opts)
  opts = opts or {}
  local current = workspace()
  local pane = current and require("agent_diff.patch").current_pane() or nil
  local bufnr = vim.api.nvim_get_current_buf()
  if not current or not pane or pane.buf ~= bufnr then
    return nil
  end

  local selected, side, revision, start_line, end_line = selected_metadata(pane, opts)
  if not selected then
    vim.notify(side, vim.log.levels.WARN, { title = "Agent Review" })
    return false
  end
  local target = {
    file = current.path,
    side = side,
    start_line = start_line,
    end_line = end_line,
    selection = "line",
    column_encoding = "utf-8-byte",
  }
  if opts.visual and vim.fn.mode(1):sub(1, 1) == "v" and #selected == 1 then
    local first = vim.fn.getpos("v")[3]
    local last = vim.fn.getpos(".")[3]
    if first > last then
      first, last = last, first
    end
    local offset = selected[1].metadata.source_col_offset or 1
    target.selection = "character"
    target.start_col = math.max(1, first - offset)
    target.end_col = math.max(target.start_col, last - offset)
  end
  return {
    tabpage = vim.api.nvim_get_current_tabpage(),
    bufnr = bufnr,
    host = "agent_patch",
    root = current.root,
    revision = {
      backend = "git",
      base_expression = selected[1].metadata.section == "staged" and "HEAD" or "INDEX",
      target_expression = selected[1].metadata.section == "staged" and "INDEX" or "WORKING",
      selected_expression = revision,
    },
    target = target,
    anchor = anchor(pane, side, revision, start_line, end_line, selected),
  }
end

local function annotation_row(pane, annotation)
  local selected_revision = annotation.revision and annotation.revision.selected_expression
  for row, metadata in pairs(pane.rows) do
    local side, revision, line = source(metadata)
    if side == annotation.target.side
      and revision == selected_revision
      and line
      and line >= annotation.target.start_line
      and line <= annotation.target.end_line
    then
      return row
    end
  end
end

function M.render(current)
  current = current or workspace()
  if not current then
    return
  end
  local session = require("agent_review.sessions").current(require("agent_review.scope").key(current.root, current.path))
  for _, pane in pairs(current.panes or {}) do
    if vim.api.nvim_buf_is_valid(pane.buf) then
      vim.api.nvim_buf_clear_namespace(pane.buf, ns, 0, -1)
      if session then
        for _, annotation in ipairs(require("agent_review.sessions").annotations(session.id)) do
          if annotation.target.file == current.path and annotation.status ~= "resolved" then
            local row = annotation_row(pane, annotation)
            if row then
              local body = annotation.body:gsub("\n", " ↵ ")
              vim.api.nvim_buf_set_extmark(pane.buf, ns, row - 1, 0, {
                virt_text = { { "  󰆈 " .. body, annotation.freshness == "stale" and "DiagnosticWarn" or "DiagnosticInfo" } },
                virt_text_pos = "eol",
                priority = 220,
              })
            end
          end
        end
      end
    end
  end
end

function M.setup()
  if initialized then
    return
  end
  initialized = true
  require("agent_review.state").on_change(function()
    vim.schedule(M.render)
  end)
end

return M
