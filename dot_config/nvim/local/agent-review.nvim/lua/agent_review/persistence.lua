local M = {}

local state = require("agent_review.state")
local sessions = require("agent_review.sessions")

local config = {
  enabled = true,
  path = nil,
  debounce_ms = 100,
}
local initialized = false
local generation = 0
local last_error = nil
local can_save = true
local needs_migration = false

local valid_author_kinds = { human = true, agent = true, forge = true }
local valid_kinds = { note = true, question = true, suggestion = true, issue = true, praise = true }
local valid_sides = { working = true, old = true, new = true, file = true, hunk = true }
local valid_statuses = { open = true, acknowledged = true, resolved = true, stale = true }
local valid_freshness = { fresh = true, reanchored = true, stale = true }

local function storage_path()
  return config.path
    or vim.env.NVIM_AGENT_REVIEW_STATE
    or (vim.fn.stdpath("state") .. "/agent-review/annotations.json")
end

local function serialize(annotation)
  return {
    id = annotation.id,
    sessionId = annotation.session_id,
    author = vim.deepcopy(annotation.author),
    body = annotation.body,
    kind = annotation.kind,
    status = annotation.status,
    freshness = annotation.freshness,
    root = annotation.root,
    host = annotation.host,
    revision = {
      backend = annotation.revision and annotation.revision.backend,
      baseExpression = annotation.revision and annotation.revision.base_expression,
      targetExpression = annotation.revision and annotation.revision.target_expression,
      selectedExpression = annotation.revision and annotation.revision.selected_expression,
    },
    target = {
      file = annotation.target.file,
      side = annotation.target.side,
      startLine = annotation.target.start_line,
      startCol = annotation.target.start_col,
      endLine = annotation.target.end_line,
      endCol = annotation.target.end_col,
      selection = annotation.target.selection,
      columnEncoding = annotation.target.column_encoding,
    },
    anchor = vim.deepcopy(annotation.anchor),
    createdAt = annotation.created_at,
    updatedAt = annotation.updated_at,
  }
end

local function positive_integer(value)
  return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function deserialize(item, index, ids)
  if type(item) ~= "table" then
    return nil, string.format("annotation %d is not an object", index)
  end
  if type(item.id) ~= "string" or item.id == "" then
    return nil, string.format("annotation %d has an invalid id", index)
  end
  if ids[item.id] then
    return nil, "duplicate annotation id: " .. item.id
  end
  if type(item.body) ~= "string" or item.body == "" then
    return nil, "annotation " .. item.id .. " has an invalid body"
  end

  local author = item.author
  if type(author) ~= "table"
    or not valid_author_kinds[author.kind]
    or type(author.name) ~= "string"
    or author.name == "" then
    return nil, "annotation " .. item.id .. " has an invalid author"
  end
  local kind = item.kind or "note"
  local status = item.status or "open"
  local freshness = item.freshness or (status == "stale" and "stale" or "fresh")
  if status == "stale" then
    status = "open"
  end
  if not valid_kinds[kind] or not valid_statuses[status] or not valid_freshness[freshness] then
    return nil, "annotation " .. item.id .. " has an invalid kind or status"
  end

  local target = item.target
  if type(target) ~= "table"
    or type(target.file) ~= "string"
    or target.file == ""
    or not valid_sides[target.side]
    or not positive_integer(target.startLine)
    or not positive_integer(target.endLine)
    or target.endLine < target.startLine then
    return nil, "annotation " .. item.id .. " has an invalid target"
  end
  if (target.startCol == nil) ~= (target.endCol == nil) then
    return nil, "annotation " .. item.id .. " has incomplete columns"
  end
  if target.startCol ~= nil then
    if not positive_integer(target.startCol)
      or not positive_integer(target.endCol)
      or (target.startLine == target.endLine and target.endCol < target.startCol) then
      return nil, "annotation " .. item.id .. " has invalid columns"
    end
  end
  local encoding = target.columnEncoding or "utf-8-byte"
  if encoding ~= "utf-8-byte" then
    return nil, "annotation " .. item.id .. " uses an unsupported column encoding"
  end

  local revision = type(item.revision) == "table" and item.revision or {}
  local root = item.root
  if root ~= nil and type(root) ~= "string" then
    return nil, "annotation " .. item.id .. " has an invalid root"
  end

  ids[item.id] = true
  return {
    id = item.id,
    session_id = item.sessionId,
    author = { kind = author.kind, name = author.name },
    body = item.body,
    kind = kind,
    status = status,
    freshness = freshness,
    root = root and vim.fs.normalize(root) or nil,
    host = item.host or "persistence",
    revision = {
      backend = revision.backend or "files",
      base_expression = revision.baseExpression,
      target_expression = revision.targetExpression,
      selected_expression = revision.selectedExpression or (target.side == "working" and "WORKING" or nil),
    },
    target = {
      file = vim.fs.normalize(target.file),
      side = target.side,
      start_line = target.startLine,
      start_col = target.startCol,
      end_line = target.endLine,
      end_col = target.endCol,
      selection = target.selection or (target.startCol and "character" or "line"),
      column_encoding = encoding,
    },
    anchor = type(item.anchor) == "table" and vim.deepcopy(item.anchor) or nil,
    created_at = item.createdAt,
    updated_at = item.updatedAt,
  }
end

local function serialize_session(session)
  return {
    id = session.id,
    name = session.name,
    workspace = session.workspace,
    root = session.root,
    file = session.file,
    backend = session.backend,
    baseRevision = session.base_revision,
    targetRevision = session.target_revision,
    status = session.status,
    createdAt = session.created_at,
    updatedAt = session.updated_at,
    archivedAt = session.archived_at,
  }
end

local function deserialize_session(item, index, ids)
  if type(item) ~= "table"
    or type(item.id) ~= "string"
    or item.id == ""
    or type(item.name) ~= "string"
    or item.name == ""
    or type(item.workspace) ~= "string"
    or item.workspace == ""
    or (item.status ~= "active" and item.status ~= "archived") then
    return nil, string.format("session %d is invalid", index)
  end
  if ids[item.id] then
    return nil, "duplicate session id: " .. item.id
  end
  if item.root ~= nil and type(item.root) ~= "string" then
    return nil, "session " .. item.id .. " has an invalid root"
  end
  if item.file ~= nil and type(item.file) ~= "string" then
    return nil, "session " .. item.id .. " has an invalid file"
  end

  ids[item.id] = true
  return {
    id = item.id,
    name = item.name,
    workspace = item.workspace,
    root = item.root and vim.fs.normalize(item.root) or nil,
    file = item.file and vim.fs.normalize(item.file) or nil,
    backend = item.backend or "files",
    base_revision = item.baseRevision,
    target_revision = item.targetRevision or "WORKING",
    status = item.status,
    created_at = item.createdAt,
    updated_at = item.updatedAt,
    archived_at = item.archivedAt,
  }
end

local function decode(contents)
  local ok, document = pcall(vim.json.decode, contents)
  if not ok then
    return nil, "failed to decode review state: " .. tostring(document)
  end
  if type(document) ~= "table"
    or (document.schemaVersion ~= 1 and document.schemaVersion ~= 2)
    or not vim.islist(document.annotations) then
    return nil, "review state has an unsupported or invalid schema"
  end

  local annotations = {}
  local annotation_ids = {}
  for index, item in ipairs(document.annotations) do
    local annotation, err = deserialize(item, index, annotation_ids)
    if not annotation then
      return nil, err
    end
    table.insert(annotations, annotation)
  end

  if document.schemaVersion == 1 then
    return {
      annotations = annotations,
      sessions = {},
      active = {},
      migrated = true,
    }
  end
  if not vim.islist(document.sessions) or type(document.activeSessions) ~= "table" then
    return nil, "review state has invalid session metadata"
  end

  local loaded_sessions = {}
  local session_ids = {}
  local session_by_id = {}
  for index, item in ipairs(document.sessions) do
    local session, err = deserialize_session(item, index, session_ids)
    if not session then
      return nil, err
    end
    table.insert(loaded_sessions, session)
    session_by_id[session.id] = session
  end

  local scope = require("agent_review.scope")
  for _, annotation in ipairs(annotations) do
    local session = annotation.session_id and session_by_id[annotation.session_id] or nil
    if not session then
      return nil, "annotation " .. annotation.id .. " references an unknown session"
    end
    if session.workspace ~= scope.for_annotation(annotation) then
      return nil, "annotation " .. annotation.id .. " does not match its session workspace"
    end
  end

  local active = {}
  for workspace, id in pairs(document.activeSessions) do
    local session = session_by_id[id]
    if type(workspace) ~= "string"
      or type(id) ~= "string"
      or not session
      or session.workspace ~= workspace
      or session.status == "archived" then
      return nil, "review state has an invalid active session"
    end
    active[workspace] = id
  end

  return {
    annotations = annotations,
    sessions = loaded_sessions,
    active = active,
    migrated = false,
  }
end

function M.load()
  if not config.enabled then
    return true, 0
  end
  local path = storage_path()
  if vim.fn.filereadable(path) ~= 1 then
    state.replace({})
    sessions.replace({}, {})
    needs_migration = false
    can_save = true
    return true, 0
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    last_error = "failed to read review state: " .. tostring(lines)
    can_save = false
    return false, last_error
  end
  local decoded, err = decode(table.concat(lines, "\n"))
  if not decoded then
    last_error = err
    can_save = false
    return false, err
  end

  state.replace(decoded.annotations)
  if decoded.migrated then
    sessions.migrate_annotations(decoded.annotations)
  else
    sessions.replace(decoded.sessions, decoded.active)
  end
  needs_migration = decoded.migrated
  last_error = nil
  can_save = true
  return true, #decoded.annotations
end

function M.save_now()
  generation = generation + 1
  if not config.enabled then
    return true
  end
  if not can_save then
    return false, last_error or "review state cannot be saved after a load failure"
  end

  require("agent_review.render").sync()
  local annotations = {}
  for _, annotation in ipairs(state.list()) do
    table.insert(annotations, serialize(annotation))
  end
  local stored_sessions, active_sessions = sessions.serialize()
  local serialized_sessions = {}
  for _, session in ipairs(stored_sessions) do
    table.insert(serialized_sessions, serialize_session(session))
  end
  local document = {
    schemaVersion = 2,
    columnConvention = "one-based-inclusive-utf-8-byte",
    savedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    sessions = serialized_sessions,
    activeSessions = active_sessions,
    annotations = annotations,
  }
  local ok, encoded = pcall(vim.json.encode, document)
  if not ok then
    last_error = "failed to encode review state: " .. tostring(encoded)
    return false, last_error
  end

  local path = storage_path()
  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  local temporary = string.format("%s.tmp.%d", path, vim.fn.getpid())
  local write_ok, write_result = pcall(vim.fn.writefile, { encoded }, temporary, "b")
  if not write_ok or write_result ~= 0 then
    pcall(vim.fn.delete, temporary)
    last_error = "failed to write review state"
    return false, last_error
  end
  vim.fn.setfperm(temporary, "rw-------")

  local renamed, rename_error = vim.uv.fs_rename(temporary, path)
  if not renamed then
    pcall(vim.fn.delete, temporary)
    last_error = "failed to replace review state: " .. tostring(rename_error)
    return false, last_error
  end
  vim.fn.setfperm(path, "rw-------")
  needs_migration = false
  last_error = nil
  return true
end

function M.schedule_save()
  if not config.enabled then
    return
  end
  generation = generation + 1
  local expected = generation
  vim.defer_fn(function()
    if expected == generation then
      local ok, err = M.save_now()
      if not ok then
        vim.notify(err, vim.log.levels.ERROR, { title = "Agent Review" })
      end
    end
  end, config.debounce_ms)
end

function M.reload()
  require("agent_review.render").clear_all()
  local ok, result = M.load()
  if ok then
    require("agent_review.render").refresh_visible()
  end
  return ok, result
end

function M.status()
  return {
    enabled = config.enabled,
    path = storage_path(),
    count = #state.list(),
    sessions = #sessions.list(nil, { include_archived = true }),
    last_error = last_error,
  }
end

function M.setup(opts)
  if initialized then
    return M
  end
  initialized = true
  config = vim.tbl_deep_extend("force", config, opts or {})

  local ok, result = M.load()
  if not ok then
    vim.notify(result, vim.log.levels.ERROR, { title = "Agent Review" })
  end
  state.on_change(function()
    can_save = true
    M.schedule_save()
  end)
  if needs_migration then
    M.schedule_save()
  end
  return M
end

return M
