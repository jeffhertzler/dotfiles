local M = {}

local state = require("agent_review.state")
local target = require("agent_review.target")
local render = require("agent_review.render")

local initialized = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Agent Review" })
end

local function create_annotation(capture, body)
  body = vim.trim(body or "")
  if body == "" then
    return nil
  end

  local session, session_err = require("agent_review.sessions").ensure_for_capture(capture)
  if not session then
    notify(session_err, vim.log.levels.ERROR)
    return nil
  end

  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local annotation = state.add({
    session_id = session.id,
    author = { kind = "human", name = vim.env.USER or "human" },
    body = body,
    kind = "note",
    status = "open",
    freshness = "fresh",
    root = capture.root,
    host = capture.host,
    revision = capture.revision,
    target = capture.target,
    anchor = capture.anchor,
    created_at = now,
    updated_at = now,
  })
  if capture.host == "agent_patch" then
    require("agent_review.patch").render()
  elseif capture.target.side == "old" and (capture.host == "codediff" or capture.host == "agent_diff") then
    render.refresh_visible()
  else
    render.refresh_buffer(capture.bufnr)
  end
  notify("Added annotation " .. annotation.id)
  return annotation
end

local function prompt_annotation(capture, opts)
  if opts.body ~= nil then
    return create_annotation(capture, opts.body)
  end
  return require("agent_review.input").open({
    capture = capture,
    on_accept = function(body)
      return create_annotation(capture, body)
    end,
  })
end

function M.add(opts)
  opts = opts or {}
  local capture = target.capture(opts)
  if not capture then
    return nil
  end
  return prompt_annotation(capture, opts)
end

function M.add_old(opts)
  opts = opts or {}
  local tabpage = vim.api.nvim_get_current_tabpage()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local agent_session = package.loaded.agent_diff and require("agent_diff").get_session(vim.api.nvim_get_current_buf()) or nil
  local is_agent_diff = agent_session and agent_session.layout == "inline"
  local adapter = require(is_agent_diff and "agent_review.agent_diff" or "agent_review.codediff")
  local candidates = is_agent_diff and adapter.old_lines_at_cursor(cursor_line)
    or adapter.old_lines_at_cursor(tabpage, cursor_line)
  if #candidates == 0 then
    notify(
      "No deleted lines at cursor; use an added replacement line or the real line adjacent to the deletion",
      vim.log.levels.WARN
    )
    return nil
  end

  local function add(candidate)
    local capture, err = is_agent_diff and adapter.capture_old_line(candidate.line)
      or adapter.capture_old_line(tabpage, candidate.line)
    if not capture then
      notify(err, vim.log.levels.WARN)
      return nil
    end
    return prompt_annotation(capture, opts)
  end

  if #candidates == 1 then
    return add(candidates[1])
  end
  vim.ui.select(candidates, {
    prompt = "Select deleted line to annotate",
    format_item = function(candidate)
      return string.format("~%d  %s", candidate.line, candidate.text)
    end,
  }, function(choice)
    if choice then
      add(choice)
    end
  end)
end

function M.list(opts)
  require("agent_review.picker").open(opts)
end

function M.workspaces()
  require("agent_review.picker").workspaces()
end

function M.sessions()
  require("agent_review.picker").sessions()
end

function M.session_new(name)
  local context = target.current_context()
  if not context or not context.path then
    notify("Open a regular file or CodeDiff buffer first", vim.log.levels.WARN)
    return nil
  end
  local session, err = require("agent_review.sessions").create({
    name = name,
    workspace = require("agent_review.scope").key(context.root, context.path),
    root = context.root,
    file = context.root and nil or context.path,
    backend = context.backend,
    base_revision = context.base_revision,
    target_revision = context.target_revision,
  })
  if not session then
    notify(err, vim.log.levels.ERROR)
    return nil
  end
  render.refresh_visible()
  notify("Created review session " .. session.name)
  return session
end

function M.session_switch(id)
  local session, err = require("agent_review.sessions").activate(id)
  if not session then
    notify(err, vim.log.levels.WARN)
    return nil
  end
  render.refresh_visible()
  notify("Active review session: " .. session.name)
  return session
end

function M.session_archive(id)
  local sessions = require("agent_review.sessions")
  local session = id and sessions.get(id) or sessions.current()
  if not session then
    notify("No active review session", vim.log.levels.WARN)
    return nil
  end
  session = sessions.archive(session.id)
  render.refresh_visible()
  notify("Archived review session " .. session.name)
  return session
end

function M.payload(opts)
  opts = opts or {}
  local annotations = opts.all and state.list() or require("agent_review.sessions").current_annotations()
  return require("agent_review.export").build(annotations, opts)
end

function M.apply(payload)
  return require("agent_review.rpc").apply(payload)
end

function M.rpc(request)
  return require("agent_review.rpc").dispatch(request)
end

function M.send(opts)
  opts = opts or {}
  local payload, err = M.payload(opts)
  if not payload then
    notify(err, vim.log.levels.WARN)
    return false
  end

  local ok, bridge = pcall(require, "agent_bridge")
  if not ok or type(bridge.send) ~= "function" then
    notify("agent-bridge.nvim does not provide send", vim.log.levels.ERROR)
    return false
  end

  return bridge.send(payload, {
    interactive_prompt = opts.interactive_prompt == true,
    submit = opts.submit == true,
    switch_to_target = opts.switch_to_target,
  }, opts.done)
end

local function annotation_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  render.refresh_buffer(bufnr)
  local context = target.context_for_buffer(bufnr)
  if not context then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local column = cursor[2] + 1

  local annotations = state.list()
  for index = #annotations, 1, -1 do
    local annotation = annotations[index]
    local item = annotation.target
    local same_revision = item.side == "working" or annotation.revision.selected_expression == context.selected_revision
    if (annotation.root or "") == (context.root or "")
      and item.file == context.path
      and item.side == context.side
      and same_revision
      and line >= item.start_line
      and line <= item.end_line then
      local in_columns = true
      if item.start_col then
        if line == item.start_line and column < item.start_col then
          in_columns = false
        end
        if line == item.end_line and column > item.end_col then
          in_columns = false
        end
      end
      if in_columns then
        return annotation
      end
    end
  end
end

function M.remove(id)
  local annotation
  if id then
    annotation = state.remove(id)
  else
    local current = annotation_at_cursor()
    annotation = current and state.remove(current.id) or nil
  end
  if not annotation then
    notify("No annotation found", vim.log.levels.WARN)
    return false
  end

  render.remove(annotation)
  notify("Removed annotation " .. annotation.id)
  return true
end

local function update_annotation(annotation, body, on_done)
  body = vim.trim(body or "")
  if body == "" then
    notify("Annotation text cannot be empty", vim.log.levels.WARN)
    return false
  end

  annotation.body = body
  annotation.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  state.changed()
  render.refresh_annotation(annotation)
  notify("Updated annotation " .. annotation.id)
  if on_done then
    on_done(annotation)
  end
  return annotation
end

function M.set_status(id, status)
  local annotation = id and state.get(id) or annotation_at_cursor()
  if not annotation then
    notify("No annotation found", vim.log.levels.WARN)
    return false
  end
  if status ~= "open" and status ~= "acknowledged" and status ~= "resolved" then
    notify("Unsupported annotation status: " .. tostring(status), vim.log.levels.WARN)
    return false
  end

  annotation.status = status
  annotation.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  state.changed()
  render.refresh_annotation(annotation)
  notify(string.format("%s annotation %s", status == "resolved" and "Resolved" or "Reopened", annotation.id))
  return annotation
end

function M.resolve(id)
  return M.set_status(id, "resolved")
end

function M.reopen(id)
  return M.set_status(id, "open")
end

function M.edit(id, opts)
  if type(id) == "table" then
    opts = id
    id = nil
  end
  opts = opts or {}
  local annotation = id and state.get(id) or annotation_at_cursor()
  if not annotation then
    notify("No annotation found", vim.log.levels.WARN)
    return false
  end

  if opts.body ~= nil then
    return update_annotation(annotation, opts.body, opts.on_done)
  end

  return require("agent_review.input").open({
    capture = { target = annotation.target },
    editing = true,
    initial = annotation.body,
    on_accept = function(body)
      return update_annotation(annotation, body, opts.on_done)
    end,
  })
end

local function remove_annotations(annotations)
  for _, annotation in ipairs(annotations) do
    state.remove(annotation.id)
  end
  for _, annotation in ipairs(annotations) do
    render.remove(annotation)
  end
  return #annotations
end

function M.clear_session()
  local session = require("agent_review.sessions").current()
  if not session then
    notify("No active review session", vim.log.levels.WARN)
    return 0
  end
  local count = remove_annotations(require("agent_review.sessions").annotations(session.id))
  notify(string.format("Cleared %d annotation%s from %s", count, count == 1 and "" or "s", session.name))
  return count
end

function M.clear_current()
  local annotations = require("agent_review.scope").current_annotations()
  local count = remove_annotations(annotations)
  notify(string.format("Cleared %d annotation%s from the current workspace", count, count == 1 and "" or "s"))
  return count
end

function M.prune(opts)
  opts = opts or {}
  local source = opts.all and state.list() or require("agent_review.scope").current_annotations()
  local removable = {}
  for _, annotation in ipairs(source) do
    if annotation.status == "resolved" or (opts.include_stale and annotation.freshness == "stale") then
      table.insert(removable, annotation)
    end
  end
  local count = remove_annotations(removable)
  notify(string.format("Pruned %d annotation%s", count, count == 1 and "" or "s"))
  return count
end

function M.clear()
  render.clear_all()
  state.clear()
  notify("Cleared all review annotations")
end

function M.annotations()
  return state.list()
end

function M.refresh(tabpage)
  render.refresh(tabpage)
end

function M.setup(opts)
  if initialized then
    return
  end
  initialized = true
  opts = opts or {}

  render.setup_highlights()
  local persistence = require("agent_review.persistence").setup(opts.persistence)
  require("agent_review.status").setup()
  require("agent_review.patch").setup()
  local group = vim.api.nvim_create_augroup("AgentReview", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      persistence.save_now()
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = render.setup_highlights,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
    callback = function(event)
      local tabpage = event.data and event.data.tabpage or vim.api.nvim_get_current_tabpage()
      vim.defer_fn(function()
        render.refresh(tabpage)
      end, 100)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "AgentDiffOpen", "AgentDiffUpdated", "AgentDiffLayout", "AgentDiffClose" },
    callback = function()
      vim.schedule(render.refresh_visible)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(event)
      vim.schedule(function()
        render.refresh_buffer(event.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
    group = group,
    callback = function(event)
      if #state.list() > 0 then
        render.revalidate_buffer(event.buf)
        persistence.schedule_save()
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function()
      vim.defer_fn(function()
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(winid) then
            render.refresh_buffer(vim.api.nvim_win_get_buf(winid))
          end
        end
      end, 50)
    end,
  })

  vim.schedule(render.refresh_visible)
  require("agent_review.commands").setup(M)
end

local function public_annotation(annotation)
  if not annotation then
    return nil
  end
  local copy = vim.deepcopy(annotation)
  copy._runtime = nil
  return copy
end

local API = {
  setup = M.setup,
  payload = M.payload,
  send = M.send,
  compose = function(opts)
    opts = vim.tbl_extend("force", opts or {}, { interactive_prompt = true })
    return M.send(opts)
  end,
  refresh = function(opts)
    if type(opts) == "number" then
      return M.refresh(opts)
    end
    opts = opts or {}
    if opts.checktime then
      vim.cmd("checktime")
      return require("agent_review.rpc").refresh()
    end
    return M.refresh()
  end,
}

local function public_annotation_result(result)
  if type(result) == "table" and result.id and result.target then
    return public_annotation(result)
  end
  return result
end

API.annotation = {
  add = function(opts) return public_annotation_result(M.add(opts)) end,
  add_old = function(opts) return public_annotation_result(M.add_old(opts)) end,
  edit = function(id, opts) return public_annotation_result(M.edit(id, opts)) end,
  remove = M.remove,
  resolve = function(id) return public_annotation_result(M.resolve(id)) end,
  reopen = function(id) return public_annotation_result(M.reopen(id)) end,
  set_status = function(id, status) return public_annotation_result(M.set_status(id, status)) end,
  at_cursor = function()
    return public_annotation(annotation_at_cursor())
  end,
  get = function(id)
    return public_annotation(state.get(id))
  end,
  list = function(opts)
    opts = opts or {}
    local source
    if opts.all then
      source = state.list()
    elseif opts.session then
      source = require("agent_review.sessions").annotations(opts.session)
    else
      source = require("agent_review.sessions").current_annotations()
    end
    return vim.tbl_map(public_annotation, source)
  end,
}

API.session = {
  current = function(workspace)
    return vim.deepcopy(require("agent_review.sessions").current(workspace))
  end,
  list = function(workspace, opts)
    return vim.deepcopy(require("agent_review.sessions").list(workspace, opts))
  end,
  create = function(name) return vim.deepcopy(M.session_new(name)) end,
  activate = function(id) return vim.deepcopy(M.session_switch(id)) end,
  archive = function(id) return vim.deepcopy(M.session_archive(id)) end,
  clear = M.clear_session,
}

API.workspace = {
  list = function()
    return vim.deepcopy(require("agent_review.scope").groups())
  end,
  clear = M.clear_current,
}

API.status = {
  counts = function() return vim.deepcopy(require("agent_review.status").counts()) end,
  text = function() return require("agent_review.status").text() end,
  has = function() return require("agent_review.status").has() end,
  open = function() return require("agent_review.status").open() end,
}

API.ui = {
  annotations = M.list,
  sessions = M.sessions,
  workspaces = M.workspaces,
}

return API
