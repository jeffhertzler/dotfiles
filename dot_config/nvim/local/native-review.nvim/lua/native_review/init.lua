local M = {}

local state = require("native_review.state")
local target = require("native_review.target")
local render = require("native_review.render")

local initialized = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Native Review" })
end

local function create_annotation(capture, body)
  body = vim.trim(body or "")
  if body == "" then
    return nil
  end

  local session, session_err = require("native_review.sessions").ensure_for_capture(capture)
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
  render.refresh_buffer(capture.bufnr)
  notify("Added annotation " .. annotation.id)
  return annotation
end

function M.add(opts)
  opts = opts or {}
  local capture = target.capture(opts)
  if not capture then
    return nil
  end

  if opts.body ~= nil then
    return create_annotation(capture, opts.body)
  end

  vim.ui.input({ prompt = "Annotation: " }, function(body)
    if body then
      create_annotation(capture, body)
    end
  end)
end

function M.list(opts)
  require("native_review.picker").open(opts)
end

function M.workspaces()
  require("native_review.picker").workspaces()
end

function M.sessions()
  require("native_review.picker").sessions()
end

function M.session_new(name)
  local context = target.context_for_buffer(vim.api.nvim_get_current_buf())
  if not context or not context.path then
    notify("Open a regular file or CodeDiff buffer first", vim.log.levels.WARN)
    return nil
  end
  local session, err = require("native_review.sessions").create({
    name = name,
    workspace = require("native_review.scope").key(context.root, context.path),
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
  local session, err = require("native_review.sessions").activate(id)
  if not session then
    notify(err, vim.log.levels.WARN)
    return nil
  end
  render.refresh_visible()
  notify("Active review session: " .. session.name)
  return session
end

function M.session_archive(id)
  local sessions = require("native_review.sessions")
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
  local annotations = opts.all and state.list() or require("native_review.sessions").current_annotations()
  return require("native_review.export").build(annotations, opts)
end

function M.apply(payload)
  return require("native_review.rpc").apply(payload)
end

function M.rpc(request)
  return require("native_review.rpc").dispatch(request)
end

function M.send(opts)
  opts = opts or {}
  local payload, err = M.payload(opts)
  if not payload then
    notify(err, vim.log.levels.WARN)
    return false
  end

  local ok, bridge = pcall(require, "agent_bridge")
  if not ok or type(bridge.send_text) ~= "function" then
    notify("agent-bridge.nvim does not provide send_text", vim.log.levels.ERROR)
    return false
  end

  return bridge.send_text(payload, {
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

  vim.ui.input({ prompt = "Edit annotation: ", default = annotation.body }, function(body)
    if body then
      update_annotation(annotation, body, opts.on_done)
    end
  end)
  return true
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
  local session = require("native_review.sessions").current()
  if not session then
    notify("No active review session", vim.log.levels.WARN)
    return 0
  end
  local count = remove_annotations(require("native_review.sessions").annotations(session.id))
  notify(string.format("Cleared %d annotation%s from %s", count, count == 1 and "" or "s", session.name))
  return count
end

function M.clear_current()
  local annotations = require("native_review.scope").current_annotations()
  local count = remove_annotations(annotations)
  notify(string.format("Cleared %d annotation%s from the current workspace", count, count == 1 and "" or "s"))
  return count
end

function M.prune(opts)
  opts = opts or {}
  local source = opts.all and state.list() or require("native_review.scope").current_annotations()
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
  local persistence = require("native_review.persistence").setup(opts.persistence)
  local group = vim.api.nvim_create_augroup("NativeReview", { clear = true })

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

  vim.api.nvim_create_user_command("NativeReviewAdd", function()
    M.add()
  end, { desc = "Annotate the current CodeDiff line" })
  vim.api.nvim_create_user_command("NativeReviewList", M.list, { desc = "List annotations in the current workspace" })
  vim.api.nvim_create_user_command("NativeReviewListAll", function()
    M.list({ all = true })
  end, { desc = "List annotations across all workspaces" })
  vim.api.nvim_create_user_command("NativeReviewWorkspaces", M.workspaces, { desc = "List review workspaces" })
  vim.api.nvim_create_user_command("NativeReviewSessions", M.sessions, { desc = "List review sessions" })
  vim.api.nvim_create_user_command("NativeReviewSessionNew", function(command)
    M.session_new(command.args)
  end, { desc = "Create and activate a named review session", nargs = "*" })
  vim.api.nvim_create_user_command("NativeReviewSessionSwitch", function(command)
    M.session_switch(command.args)
  end, { desc = "Activate a review session by ID", nargs = 1 })
  vim.api.nvim_create_user_command("NativeReviewSessionArchive", function(command)
    M.session_archive(command.args ~= "" and command.args or nil)
  end, { desc = "Archive the active review session or an ID", nargs = "?" })
  vim.api.nvim_create_user_command("NativeReviewSend", function(command)
    M.send({ submit = command.bang, switch_to_target = not command.bang })
  end, { desc = "Send current-workspace annotations to an agent", bang = true })
  vim.api.nvim_create_user_command("NativeReviewSendAll", function(command)
    M.send({ all = true, submit = command.bang, switch_to_target = not command.bang })
  end, { desc = "Send annotations from every workspace", bang = true })
  vim.api.nvim_create_user_command("NativeReviewCompose", function()
    M.send({ interactive_prompt = true })
  end, { desc = "Compose an agent message with review annotations" })
  vim.api.nvim_create_user_command("NativeReviewRemove", function(command)
    M.remove(command.args ~= "" and command.args or nil)
  end, { desc = "Remove the annotation at the cursor or by ID", nargs = "?" })
  vim.api.nvim_create_user_command("NativeReviewEdit", function(command)
    M.edit(command.args ~= "" and command.args or nil)
  end, { desc = "Edit the annotation at the cursor or by ID", nargs = "?" })
  vim.api.nvim_create_user_command("NativeReviewSessionClear", M.clear_session, { desc = "Clear active-session annotations" })
  vim.api.nvim_create_user_command("NativeReviewClearCurrent", M.clear_current, { desc = "Clear current-workspace annotations" })
  vim.api.nvim_create_user_command("NativeReviewPrune", function(command)
    M.prune({ include_stale = command.bang })
  end, { desc = "Prune resolved annotations; bang also prunes stale annotations", bang = true })
  vim.api.nvim_create_user_command("NativeReviewClear", M.clear, { desc = "Clear all review annotations" })
  vim.api.nvim_create_user_command("NativeReviewSave", function()
    local ok, err = persistence.save_now()
    notify(ok and "Saved review annotations" or err, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end, { desc = "Save review annotations" })
  vim.api.nvim_create_user_command("NativeReviewReload", function()
    local ok, result = persistence.reload()
    notify(ok and string.format("Reloaded %d review annotations", result) or result, ok and vim.log.levels.INFO or vim.log.levels.ERROR)
  end, { desc = "Reload review annotations from disk" })
end

return M
