local M = {}

local render = require("native_review.render")
local state = require("native_review.state")
local target_util = require("native_review.target")

local valid_kinds = { note = true, question = true, suggestion = true, issue = true, praise = true }
local valid_sides = { working = true, old = true, new = true, file = true, hunk = true }
local valid_statuses = { open = true, acknowledged = true, resolved = true, stale = true }

local function failure(message, index, field)
  return {
    ok = false,
    error = message,
    index = index,
    field = field,
  }
end

local function positive_integer(value)
  return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function normalized_root(root)
  if root == nil then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(root, ":p")):gsub("/$", "")
end

local function normalized_file(file, root)
  file = vim.fs.normalize(file)
  if root and vim.startswith(file, root .. "/") then
    return file:sub(#root + 2)
  end
  return file
end

local function default_context()
  return target_util.context_for_buffer(vim.api.nvim_get_current_buf())
end

local function find_target_buffer(annotation)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local context = target_util.context_for_buffer(bufnr)
      local same_revision = annotation.target.side == "working"
        or (context and annotation.revision.selected_expression == context.selected_revision)
      if context
        and (context.root or "") == (annotation.root or "")
        and context.path == annotation.target.file
        and context.side == annotation.target.side
        and same_revision then
        return bufnr
      end
    end
  end
end

local function validate_comment(comment, index, defaults, batch_ids)
  if type(comment) ~= "table" then
    return nil, failure("comment must be an object", index)
  end
  if comment.id ~= nil and (type(comment.id) ~= "string" or comment.id == "" or comment.id:find("%s")) then
    return nil, failure("id must be a non-empty string without whitespace", index, "id")
  end
  if comment.id and (batch_ids[comment.id] or state.get(comment.id)) then
    return nil, failure("annotation id already exists: " .. comment.id, index, "id")
  end
  if type(comment.body) ~= "string" or vim.trim(comment.body) == "" then
    return nil, failure("body must be a non-empty string", index, "body")
  end
  if #comment.body > 100000 then
    return nil, failure("body exceeds 100000 bytes", index, "body")
  end

  local wire_target = comment.target
  if type(wire_target) ~= "table" then
    return nil, failure("target must be an object", index, "target")
  end
  if type(wire_target.file) ~= "string" or wire_target.file == "" or wire_target.file:find("%z") then
    return nil, failure("target.file must be a non-empty path", index, "target.file")
  end

  local side = wire_target.side or "working"
  if not valid_sides[side] then
    return nil, failure("unsupported target.side: " .. tostring(side), index, "target.side")
  end
  local start_line = wire_target.startLine
  local end_line = wire_target.endLine or start_line
  if not positive_integer(start_line) then
    return nil, failure("target.startLine must be a positive integer", index, "target.startLine")
  end
  if not positive_integer(end_line) or end_line < start_line then
    return nil, failure("target.endLine must be an integer at or after startLine", index, "target.endLine")
  end

  local start_col = wire_target.startCol
  local end_col = wire_target.endCol
  if (start_col == nil) ~= (end_col == nil) then
    return nil, failure("target.startCol and target.endCol must be provided together", index, "target")
  end
  if start_col ~= nil then
    if not positive_integer(start_col) or not positive_integer(end_col) then
      return nil, failure("target columns must be positive integers", index, "target")
    end
    if start_line == end_line and end_col < start_col then
      return nil, failure("target.endCol must be at or after startCol on one line", index, "target.endCol")
    end
  end
  local encoding = wire_target.columnEncoding or "utf-8-byte"
  if encoding ~= "utf-8-byte" then
    return nil, failure("only utf-8-byte columns are currently supported", index, "target.columnEncoding")
  end

  local kind = comment.kind or "note"
  local status = comment.status or "open"
  if not valid_kinds[kind] then
    return nil, failure("unsupported kind: " .. tostring(kind), index, "kind")
  end
  if not valid_statuses[status] then
    return nil, failure("unsupported status: " .. tostring(status), index, "status")
  end

  local root_value = comment.root or defaults.root
  if root_value ~= nil and type(root_value) ~= "string" then
    return nil, failure("root must be a path string", index, "root")
  end
  local root = normalized_root(root_value)
  local revision = comment.revision or {}
  if type(revision) ~= "table" then
    return nil, failure("revision must be an object", index, "revision")
  end
  local selected_revision = revision.selectedExpression or (side == "working" and "WORKING" or nil)
  if side ~= "working" and (type(selected_revision) ~= "string" or selected_revision == "") then
    return nil, failure("non-working targets require revision.selectedExpression", index, "revision.selectedExpression")
  end

  local author_name = type(comment.author) == "table" and comment.author.name or defaults.author
  if type(author_name) ~= "string" or author_name == "" then
    return nil, failure("author name must be a non-empty string", index, "author.name")
  end

  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local annotation = {
    id = comment.id,
    author = {
      kind = "agent",
      name = author_name,
    },
    body = vim.trim(comment.body),
    kind = kind,
    status = status,
    root = root,
    host = "rpc",
    revision = {
      backend = revision.backend or defaults.backend,
      base_expression = revision.baseExpression,
      target_expression = revision.targetExpression,
      selected_expression = selected_revision,
    },
    target = {
      file = normalized_file(wire_target.file, root),
      side = side,
      start_line = start_line,
      start_col = start_col,
      end_line = end_line,
      end_col = end_col,
      selection = start_col and "character" or "line",
      column_encoding = encoding,
    },
    anchor = type(comment.anchor) == "table" and vim.deepcopy(comment.anchor) or nil,
    created_at = now,
    updated_at = now,
  }

  local bufnr = find_target_buffer(annotation)
  if bufnr then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if end_line > line_count then
      return nil, failure("target line range exceeds the loaded buffer", index, "target.endLine")
    end
    if start_col then
      local start_text = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, start_line, false)[1] or ""
      local end_text = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1] or ""
      if start_col > #start_text + 1 or end_col > #end_text + 1 then
        return nil, failure("target column range exceeds the loaded buffer", index, "target")
      end
    end
  end
  if not annotation.anchor and bufnr then
    annotation.anchor = target_util.anchor_for_buffer(bufnr, annotation.target)
  end
  if comment.id then
    batch_ids[comment.id] = true
  end
  return annotation
end

local function serialize(annotation)
  return {
    id = annotation.id,
    author = vim.deepcopy(annotation.author),
    body = annotation.body,
    kind = annotation.kind,
    status = annotation.status,
    root = annotation.root,
    revision = {
      backend = annotation.revision.backend,
      baseExpression = annotation.revision.base_expression,
      targetExpression = annotation.revision.target_expression,
      selectedExpression = annotation.revision.selected_expression,
    },
    target = {
      file = annotation.target.file,
      side = annotation.target.side,
      startLine = annotation.target.start_line,
      startCol = annotation.target.start_col,
      endLine = annotation.target.end_line,
      endCol = annotation.target.end_col,
      columnEncoding = annotation.target.column_encoding,
    },
    anchor = vim.deepcopy(annotation.anchor),
    createdAt = annotation.created_at,
    updatedAt = annotation.updated_at,
  }
end

function M.apply(payload)
  if type(payload) ~= "table" then
    return failure("payload must be an object")
  end
  if payload.schemaVersion ~= nil and payload.schemaVersion ~= 1 then
    return failure("unsupported schemaVersion: " .. tostring(payload.schemaVersion), nil, "schemaVersion")
  end
  if not vim.islist(payload.comments) or #payload.comments == 0 then
    return failure("comments must be a non-empty array", nil, "comments")
  end
  if #payload.comments > 500 then
    return failure("a batch may contain at most 500 comments", nil, "comments")
  end

  local context = default_context()
  local defaults = {
    root = payload.root or (context and context.root),
    backend = payload.backend or (context and context.backend) or "files",
    author = payload.author or "agent",
  }
  local pending = {}
  local batch_ids = {}
  for index, comment in ipairs(payload.comments) do
    local annotation, err = validate_comment(comment, index, defaults, batch_ids)
    if not annotation then
      return err
    end
    table.insert(pending, annotation)
  end

  local ids = {}
  for _, annotation in ipairs(pending) do
    state.add(annotation)
    table.insert(ids, annotation.id)
  end
  render.refresh_visible()
  vim.notify(string.format("Imported %d agent annotation%s", #ids, #ids == 1 and "" or "s"), vim.log.levels.INFO, { title = "Native Review" })
  return { ok = true, count = #ids, ids = ids }
end

local function validate_ids(payload)
  if type(payload) ~= "table" or not vim.islist(payload.ids) or #payload.ids == 0 then
    return nil, failure("ids must be a non-empty array", nil, "ids")
  end
  if #payload.ids > 500 then
    return nil, failure("a batch may contain at most 500 ids", nil, "ids")
  end

  local annotations = {}
  local seen = {}
  for index, id in ipairs(payload.ids) do
    if type(id) ~= "string" or id == "" then
      return nil, failure("id must be a non-empty string", index, "ids")
    end
    if seen[id] then
      return nil, failure("duplicate id in batch: " .. id, index, "ids")
    end
    local annotation = state.get(id)
    if not annotation then
      return nil, failure("annotation not found: " .. id, index, "ids")
    end
    seen[id] = true
    table.insert(annotations, annotation)
  end
  return annotations
end

function M.update(payload)
  if type(payload) ~= "table" or not vim.islist(payload.updates) or #payload.updates == 0 then
    return failure("updates must be a non-empty array", nil, "updates")
  end
  if #payload.updates > 500 then
    return failure("a batch may contain at most 500 updates", nil, "updates")
  end

  local pending = {}
  local seen = {}
  for index, update in ipairs(payload.updates) do
    if type(update) ~= "table" then
      return failure("update must be an object", index, "updates")
    end
    if type(update.id) ~= "string" or update.id == "" then
      return failure("update.id must be a non-empty string", index, "id")
    end
    if seen[update.id] then
      return failure("duplicate id in batch: " .. update.id, index, "id")
    end
    local annotation = state.get(update.id)
    if not annotation then
      return failure("annotation not found: " .. update.id, index, "id")
    end
    if update.body == nil and update.kind == nil and update.status == nil then
      return failure("update must include body, kind, or status", index, "updates")
    end

    if update.body ~= nil and type(update.body) ~= "string" then
      return failure("body must be a string", index, "body")
    end
    local body = update.body ~= nil and vim.trim(update.body) or annotation.body
    local kind = update.kind ~= nil and update.kind or annotation.kind
    local status = update.status ~= nil and update.status or annotation.status
    if body == "" or #body > 100000 then
      return failure("body must contain between 1 and 100000 bytes", index, "body")
    end
    if type(kind) ~= "string" or not valid_kinds[kind] then
      return failure("unsupported kind: " .. tostring(kind), index, "kind")
    end
    if type(status) ~= "string" or not valid_statuses[status] then
      return failure("unsupported status: " .. tostring(status), index, "status")
    end

    seen[update.id] = true
    table.insert(pending, { annotation = annotation, body = body, kind = kind, status = status })
  end

  local ids = {}
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  for _, update in ipairs(pending) do
    update.annotation.body = update.body
    update.annotation.kind = update.kind
    update.annotation.status = update.status
    update.annotation.updated_at = now
    table.insert(ids, update.annotation.id)
  end
  render.refresh_visible()
  vim.notify(string.format("Updated %d annotation%s", #ids, #ids == 1 and "" or "s"), vim.log.levels.INFO, { title = "Native Review" })
  return { ok = true, count = #ids, ids = ids }
end

function M.resolve(payload)
  local annotations, err = validate_ids(payload)
  if not annotations then
    return err
  end

  local ids = {}
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  for _, annotation in ipairs(annotations) do
    annotation.status = "resolved"
    annotation.updated_at = now
    table.insert(ids, annotation.id)
  end
  render.refresh_visible()
  vim.notify(string.format("Resolved %d annotation%s", #ids, #ids == 1 and "" or "s"), vim.log.levels.INFO, { title = "Native Review" })
  return { ok = true, count = #ids, ids = ids }
end

function M.remove(payload)
  local annotations, err = validate_ids(payload)
  if not annotations then
    return err
  end

  local ids = {}
  for _, annotation in ipairs(annotations) do
    state.remove(annotation.id)
    table.insert(ids, annotation.id)
  end
  for _, annotation in ipairs(annotations) do
    render.remove(annotation)
  end
  vim.notify(string.format("Removed %d annotation%s", #ids, #ids == 1 and "" or "s"), vim.log.levels.INFO, { title = "Native Review" })
  return { ok = true, count = #ids, ids = ids }
end

function M.list()
  local comments = {}
  for _, annotation in ipairs(state.list()) do
    table.insert(comments, serialize(annotation))
  end
  return { ok = true, schemaVersion = 1, comments = comments }
end

function M.context()
  local context = default_context()
  return {
    ok = true,
    schemaVersion = 1,
    server = vim.v.servername,
    current = context and {
      root = context.root,
      backend = context.backend,
      file = context.path,
      side = context.side,
      selectedRevision = context.selected_revision,
    } or vim.NIL,
  }
end

function M.dispatch(request)
  if type(request) ~= "table" then
    return failure("request must be an object")
  end
  if request.operation == "apply" then
    return M.apply(request.payload or request)
  elseif request.operation == "update" then
    return M.update(request.payload or request)
  elseif request.operation == "resolve" then
    return M.resolve(request.payload or request)
  elseif request.operation == "remove" then
    return M.remove(request.payload or request)
  elseif request.operation == "list" then
    return M.list()
  elseif request.operation == "context" then
    return M.context()
  end
  return failure("unsupported operation: " .. tostring(request.operation), nil, "operation")
end

return M
