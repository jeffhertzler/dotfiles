local review = require("agent_review")
local contexts = require("agent_review.context")
local picker = require("agent_review.picker")
local scope = require("agent_review.scope")
local root = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(root, "p")
vim.cmd("edit " .. vim.fn.fnameescape(vim.env.AGENT_REVIEW_TEST_FILE))
local code_buf = vim.api.nvim_get_current_buf()
local code = assert(review.annotation.add({ body = "ordinary review" }))
local ordinary = contexts.ordinary()
assert(code.id == "review-1")

local opened = {}
local snacks = package.loaded.snacks
package.loaded.snacks = { picker = function(opts) opened[#opened + 1] = opts end }
local closed = { close = function() end }
local function last() return assert(opened[#opened]) end
local function unchanged()
  assert(ordinary.state.get(code.id).body == "ordinary review")
  assert(ordinary.state.get(code.id).status == "open")
  assert(ordinary.sessions.get(code.session_id).status == "active")
end
local function fixture(name)
  local directory = root .. "/" .. name
  vim.fn.mkdir(directory, "p")
  local path = directory .. "/source.md"
  vim.fn.writefile({ "feedback source", "second line" }, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  local context = assert(contexts.attach(buf, { feedbackDirectory = directory, sourcePath = path }))
  local annotation = assert(review.annotation.add({ body = name }))
  assert(annotation.id == code.id)
  return buf, context, annotation
end
local function wipe(buf)
  vim.api.nvim_set_current_buf(code_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end
-- Keep scheduled reopen callbacks pending until after the focus/store changes.
local function deferred(action)
  local schedule, pending = vim.schedule, {}
  vim.schedule = function(fn) pending[#pending + 1] = fn end
  local ok, err = pcall(action)
  vim.schedule = schedule
  assert(ok, err)
  return function() for _, fn in ipairs(pending) do fn() end end
end

-- All-annotations queries and delayed resolve/reopen stay in the captured store.
local buf, context, annotation = fixture("resolve")
vim.api.nvim_set_current_buf(code_buf)
local opts = { all = true, bufnr = buf }
picker.open(opts)
assert(opts._context == nil, "picker must not mutate caller options")
local first = last()
assert(first.items[1].annotation.body == "resolve")
wipe(buf)
local flush = deferred(function() first.actions.toggle_resolved(closed, first.items[1]) end)
assert(context.state.get(annotation.id).status == "resolved")
unchanged()
flush()
assert(last() ~= first and last().items[1].annotation.body == "resolve")
local resolved = last()
flush = deferred(function() resolved.actions.toggle_resolved(closed, resolved.items[1]) end)
flush()
assert(context.state.get(annotation.id).status == "open")
unchanged()

-- Edit invokes the real annotation API after the source buffer has gone away.
buf, context, annotation = fixture("edit")
picker.open()
local editing = last()
wipe(buf)
local input, accept = package.loaded["agent_review.input"]
package.loaded["agent_review.input"] = { open = function(opts) accept = opts.on_accept end }
editing.actions.edit_annotation(closed, editing.items[1])
assert(accept and accept("edited feedback"))
assert(context.state.get(annotation.id).body == "edited feedback")
assert(contexts.release(context))
assert(not accept("closed edit"))
assert(context.state.get(annotation.id).body == "edited feedback")
unchanged()
package.loaded["agent_review.input"] = input

-- Remove and its remaining-annotations query use the original scope and store.
buf, context, annotation = fixture("remove")
local remaining = assert(review.annotation.add({ body = "remaining feedback" }))
local workspace = scope.current()
picker.open({ scope = workspace })
local removing = last()
wipe(buf)
flush = deferred(function() removing.actions.remove_annotation(closed, removing.items[1]) end)
assert(not context.state.get(annotation.id))
unchanged()
flush()
assert(last() ~= removing and #last().items == 1)
assert(last().items[1].annotation.id == remaining.id)
assert(last().items[1].annotation.body == "remaining feedback")
assert(#scope.list(workspace, context) == 1)
assert(scope.groups(context)[1].key == workspace)

-- A default picker pins its active session, not whichever workspace gains focus.
buf, context, annotation = fixture("default-scope")
picker.open()
first = last()
flush = deferred(function() first.actions.toggle_resolved(closed, first.items[1]) end)
wipe(buf)
flush()
assert(last() ~= first and last().items[1].annotation.body == "default-scope")
unchanged()

-- Session actions, reopen, and confirmation preserve both store and workspace.
buf, context, annotation = fixture("sessions")
picker.sessions()
first = last()
wipe(buf)
flush = deferred(function() first.actions.toggle_archive(closed, first.items[1]) end)
assert(context.sessions.get(annotation.session_id).status == "archived")
unchanged()
flush()
assert(last() ~= first and #last().items == 1)
assert(last().items[1].session.workspace == scope.for_annotation(annotation))
last().confirm(closed, last().items[1])
assert(context.sessions.get(annotation.session_id).status == "active")
assert(last().items[1].annotation.body == "sessions")
unchanged()

-- The workspace -> session -> annotations chain must never adopt picker focus.
buf, context = fixture("workspaces")
picker.workspaces()
first = last()
wipe(buf)
first.confirm(closed, first.items[1])
assert(last().items[1].session.workspace == first.items[1].group.key)
last().confirm(closed, last().items[1])
assert(last().items[1].annotation.body == "workspaces")
unchanged()

-- A closed context refuses every stale action, including queued reopen work.
buf, context, annotation = fixture("closed")
picker.open()
local stale_annotations = last()
picker.sessions()
local stale_sessions = last()
picker.workspaces()
local stale_workspaces = last()
flush = deferred(function()
  stale_annotations.actions.toggle_resolved(closed, stale_annotations.items[1])
  stale_sessions.actions.toggle_archive(closed, stale_sessions.items[1])
end)
wipe(buf)
assert(contexts.release(context))
local snapshot = vim.deepcopy(context.state.list())
local session_snapshot = vim.deepcopy(context.sessions.list(nil, { include_archived = true }))
local count = #opened
flush()
for _, action in pairs(stale_annotations.actions) do action(closed, stale_annotations.items[1]) end
stale_annotations.confirm(closed, stale_annotations.items[1])
stale_sessions.actions.toggle_archive(closed, stale_sessions.items[1])
stale_sessions.confirm(closed, stale_sessions.items[1])
stale_workspaces.confirm(closed, stale_workspaces.items[1])
assert(#opened == count)
assert(vim.deep_equal(snapshot, context.state.list()))
assert(vim.deep_equal(session_snapshot, context.sessions.list(nil, { include_archived = true })))
assert(#scope.list(nil, context) == 0 and #scope.groups(context) == 0)
assert(not review.annotation.remove(annotation.id, { _context = context }))
assert(not review.annotation.resolve(annotation.id, { _context = context }))
assert(not review.annotation.edit(annotation.id, { _context = context, body = "late" }))
unchanged()

-- vim.ui.select fallback callbacks retain the same origin through both levels.
local preload, select = package.preload.snacks, vim.ui.select
package.loaded.snacks = nil
package.preload.snacks = function() error("Snacks unavailable for fallback test") end
local selected
vim.ui.select = function(items, _, callback) selected = { items = items, callback = callback } end
buf, context = fixture("fallback")
picker.workspaces()
local workspaces = selected
wipe(buf)
workspaces.callback(workspaces.items[1])
local sessions = selected
assert(sessions ~= workspaces)
sessions.callback(sessions.items[1])
assert(selected.items[1].annotation.body == "fallback")
unchanged()
assert(contexts.release(context))
selected = nil
workspaces.callback(workspaces.items[1])
sessions.callback(sessions.items[1])
assert(selected == nil)
vim.ui.select, package.preload.snacks = select, preload
package.loaded.snacks = { picker = function(opts) opened[#opened + 1] = opts end }

-- Ordinary APIs still default to the current buffer; code pickers stay ordinary
-- if feedback gains focus while they are open.
vim.api.nvim_set_current_buf(code_buf)
assert(review.annotation.resolve(code.id).status == "resolved")
assert(review.annotation.reopen(code.id).status == "open")
assert(review.annotation.edit(code.id, { body = "ordinary review" }))
picker.open()
first = last()
buf, context, annotation = fixture("ordinary-origin")
flush = deferred(function() first.actions.toggle_resolved(closed, first.items[1]) end)
flush()
assert(ordinary.state.get(code.id).status == "resolved")
assert(context.state.get(annotation.id).status == "open")
assert(last().items[1].annotation.body == "ordinary review")
package.loaded.snacks = snacks
