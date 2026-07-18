local M = {}

local state = require("native_review.state")
local scope = require("native_review.scope")

local sessions = {}
local active_by_workspace = {}
local next_id = 1

local function now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function update_next_id(session)
  local number = session.id and session.id:match("^session%-(%d+)$")
  if number then
    next_id = math.max(next_id, tonumber(number) + 1)
  end
end

local function generated_id()
  local id
  repeat
    id = string.format("session-%d", next_id)
    next_id = next_id + 1
  until not M.get(id)
  return id
end

local function default_name(opts)
  local base = opts.base_revision
  local target_revision = opts.target_revision
  if base and target_revision then
    return string.format("%s → %s", base, target_revision)
  elseif base then
    return string.format("%s → working tree", base)
  end
  return "Working tree"
end

function M.get(id)
  for _, session in ipairs(sessions) do
    if session.id == id then
      return session
    end
  end
end

function M.list(workspace_key, opts)
  opts = opts or {}
  local result = {}
  for _, session in ipairs(sessions) do
    if (not workspace_key or session.workspace == workspace_key)
      and (opts.include_archived or session.status ~= "archived") then
      table.insert(result, session)
    end
  end
  table.sort(result, function(first, second)
    return (first.updated_at or first.created_at or "") > (second.updated_at or second.created_at or "")
  end)
  return result
end

function M.current(workspace_key)
  workspace_key = workspace_key or scope.current()
  if not workspace_key then
    return nil
  end

  local active_id = active_by_workspace[workspace_key]
  local active = active_id and M.get(active_id) or nil
  if active and active.status ~= "archived" then
    return active
  end

  active_by_workspace[workspace_key] = nil
  local available = M.list(workspace_key)
  if available[1] then
    active_by_workspace[workspace_key] = available[1].id
    state.changed()
    return available[1]
  end
end

function M.create(opts)
  opts = opts or {}
  if type(opts.workspace) ~= "string" or opts.workspace == "" then
    return nil, "session workspace is required"
  end
  local name = vim.trim(opts.name or "")
  if name == "" then
    name = default_name(opts)
  end

  local timestamp = now()
  local session = {
    id = opts.id or generated_id(),
    name = name,
    workspace = opts.workspace,
    root = opts.root,
    file = opts.file,
    backend = opts.backend or "files",
    base_revision = opts.base_revision,
    target_revision = opts.target_revision or "WORKING",
    status = opts.status or "active",
    created_at = opts.created_at or timestamp,
    updated_at = opts.updated_at or timestamp,
    archived_at = opts.archived_at,
  }
  if M.get(session.id) then
    return nil, "session id already exists: " .. session.id
  end

  table.insert(sessions, session)
  update_next_id(session)
  if session.status ~= "archived" then
    active_by_workspace[session.workspace] = session.id
  end
  state.changed()
  return session
end

function M.activate(id)
  local session = M.get(id)
  if not session then
    return nil, "session not found: " .. tostring(id)
  end
  if session.status == "archived" then
    session.status = "active"
    session.archived_at = nil
  end
  session.updated_at = now()
  active_by_workspace[session.workspace] = session.id
  state.changed()
  return session
end

function M.archive(id)
  local session = M.get(id)
  if not session then
    return nil, "session not found: " .. tostring(id)
  end
  session.status = "archived"
  session.archived_at = now()
  session.updated_at = session.archived_at
  if active_by_workspace[session.workspace] == session.id then
    active_by_workspace[session.workspace] = nil
  end
  state.changed()
  return session
end

function M.ensure_for_capture(capture)
  local workspace = scope.key(capture.root, capture.target and capture.target.file)
  local current = M.current(workspace)
  if current then
    return current
  end
  return M.create({
    workspace = workspace,
    root = capture.root,
    file = capture.root and nil or (capture.target and capture.target.file),
    backend = capture.revision and capture.revision.backend,
    base_revision = capture.revision and capture.revision.base_expression,
    target_revision = capture.revision and capture.revision.target_expression,
  })
end

function M.assign(annotation, requested_id)
  if requested_id then
    local requested = M.get(requested_id)
    if not requested then
      return nil, "session not found: " .. requested_id
    end
    if requested.workspace ~= scope.for_annotation(annotation) then
      return nil, "session does not belong to the annotation workspace"
    end
    annotation.session_id = requested.id
    return requested
  end

  local capture = {
    root = annotation.root,
    target = annotation.target,
    revision = annotation.revision,
  }
  local session, err = M.ensure_for_capture(capture)
  if not session then
    return nil, err
  end
  annotation.session_id = session.id
  return session
end

function M.annotations(session_id)
  local result = {}
  for _, annotation in ipairs(state.list()) do
    if annotation.session_id == session_id then
      table.insert(result, annotation)
    end
  end
  return result
end

function M.current_annotations()
  local current = M.current()
  return current and M.annotations(current.id) or {}
end

function M.counts(session_id)
  local counts = { total = 0, open = 0, resolved = 0, stale = 0 }
  for _, annotation in ipairs(M.annotations(session_id)) do
    counts.total = counts.total + 1
    if annotation.status == "resolved" then
      counts.resolved = counts.resolved + 1
    else
      counts.open = counts.open + 1
    end
    if annotation.freshness == "stale" then
      counts.stale = counts.stale + 1
    end
  end
  return counts
end

function M.serialize()
  return vim.deepcopy(sessions), vim.deepcopy(active_by_workspace)
end

function M.replace(loaded_sessions, loaded_active)
  sessions = loaded_sessions or {}
  active_by_workspace = loaded_active or {}
  next_id = 1
  for _, session in ipairs(sessions) do
    update_next_id(session)
  end
end

function M.migrate_annotations(annotations)
  sessions = {}
  active_by_workspace = {}
  next_id = 1
  local by_workspace = {}

  for _, annotation in ipairs(annotations) do
    local workspace = scope.for_annotation(annotation)
    local session = by_workspace[workspace]
    if not session then
      local timestamp = annotation.created_at or now()
      session = {
        id = generated_id(),
        name = "Migrated review",
        workspace = workspace,
        root = annotation.root,
        file = annotation.root and nil or annotation.target.file,
        backend = annotation.revision and annotation.revision.backend or "files",
        base_revision = annotation.revision and annotation.revision.base_expression,
        target_revision = annotation.revision and annotation.revision.target_expression or "WORKING",
        status = "active",
        created_at = timestamp,
        updated_at = annotation.updated_at or timestamp,
      }
      table.insert(sessions, session)
      by_workspace[workspace] = session
      active_by_workspace[workspace] = session.id
    end
    annotation.session_id = session.id
  end
end

return M
