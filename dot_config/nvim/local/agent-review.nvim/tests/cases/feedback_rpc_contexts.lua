local review = require("agent_review")
local contexts = require("agent_review.context")
local rpc = require("agent_review.rpc")
local root = assert(vim.env.AGENT_REVIEW_TEST_TMP)
local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
local state_path = assert(vim.env.NVIM_AGENT_REVIEW_STATE)
vim.fn.mkdir(root .. "/feedback/.git", "p")
local source = root .. "/feedback/source.md"
vim.fn.writefile({ "feedback first", "feedback second", "feedback last" }, source)

vim.cmd("edit " .. vim.fn.fnameescape(file))
local code_buf = vim.api.nvim_get_current_buf()
local code_tab = vim.api.nvim_get_current_tabpage()
local code = contexts.ordinary()
local code_annotation = assert(review.annotation.add({ body = "code original" }))
code_annotation = assert(code.state.get(code_annotation.id))
local code_session = assert(review.session.current())
assert(code_annotation.id == "review-1")

vim.cmd("tabedit " .. vim.fn.fnameescape(source))
local feedback_buf = vim.api.nvim_get_current_buf()
local feedback = assert(contexts.attach(feedback_buf, {
  schemaVersion = 1,
  reader = true,
  piSessionId = "rpc-test",
  assistantMessageId = "one",
  feedbackDirectory = root .. "/feedback",
  sourcePath = source,
  feedbackPath = root .. "/feedback/feedback.json",
}))
local feedback_annotation = assert(review.annotation.add({ body = "feedback original" }))
feedback_annotation = assert(feedback.state.get(feedback_annotation.id))
assert(feedback_annotation.id == code_annotation.id)
assert(feedback_annotation.session_id == code_session.id)
local feedback_only = assert(review.annotation.add({ body = "feedback only" }))
feedback_only = assert(feedback.state.get(feedback_only.id))
assert(feedback.sessions.create({
  id = "feedback-only-session",
  workspace = require("agent_review.scope").for_annotation(code_annotation),
}))
assert(feedback.persistence.save_now())
local feedback_path = root .. "/feedback/annotations.json"
local feedback_before = vim.fn.readfile(feedback_path)
local function unchanged_feedback()
  assert(vim.api.nvim_get_current_buf() == feedback_buf, "RPC must not switch buffers")
  assert(#feedback.state.list() == 2)
  assert(feedback_annotation.body == "feedback original")
  assert(feedback_annotation.status == "open")
  assert(feedback.state.get(feedback_only.id) == feedback_only)
  assert(vim.deep_equal(feedback_before, vim.fn.readfile(feedback_path)), "RPC wrote feedback state")
end
local function comment(id, body)
  return { id = id, body = body, target = { file = file, startLine = 2 } }
end
local function dispatch(operation, payload)
  return rpc.dispatch({ operation = operation, payload = payload })
end

-- Both contexts own review-1 and session-1. Explicit code targets and session
-- IDs must be validated and assigned in the ordinary store while feedback has focus.
local applied = dispatch("apply", { sessionId = code_session.id, comments = {
  comment("code-agent", "code finding"),
} })
assert(applied.ok, vim.inspect(applied))
local finding = assert(code.state.get("code-agent"), "explicit code target went into feedback")
assert(finding.session_id == code_session.id)
assert(finding.root == code_annotation.root, "feedback root leaked into code defaults")
assert(finding.anchor.selected[1] == "local value = 200")
unchanged_feedback()

-- Duplicate IDs are scoped to code, not to whichever store currently has focus.
assert(dispatch("apply", { comments = { comment(feedback_only.id, "code with feedback ID") } }).ok)
local duplicate = dispatch("apply", { comments = { comment(code_annotation.id, "duplicate") } })
assert(not duplicate.ok and duplicate.field == "id")
local before_count = #code.state.list()
local before_sessions = #code.sessions.list(nil, { include_archived = true })
local invalid = dispatch("apply", { comments = {
  comment("must-not-apply", "valid first"),
  vim.tbl_extend("force", comment("wrong-session", "invalid second"), { sessionId = "feedback-only-session" }),
} })
assert(not invalid.ok and invalid.index == 2 and invalid.field == "sessionId")
assert(#code.state.list() == before_count and not code.state.get("must-not-apply"))
assert(#code.sessions.list(nil, { include_archived = true }) == before_sessions)
invalid = dispatch("apply", { comments = {
  comment("must-not-apply", "valid first"),
  { body = "bad range", target = { file = file, startLine = 999 } },
} })
assert(not invalid.ok and invalid.index == 2 and invalid.field == "target.endLine")
assert(#code.state.list() == before_count and not code.state.get("must-not-apply"))
local wrong_workspace = assert(code.sessions.create({ id = "wrong-workspace", workspace = "file:/other" }))
invalid = dispatch("apply", { sessionId = wrong_workspace.id, comments = { comment("wrong", "wrong") } })
assert(not invalid.ok and invalid.field == "sessionId")

-- Every mutation validates the whole batch before changing either store.
invalid = dispatch("update", { updates = {
  { id = code_annotation.id, body = "must not update" }, { id = "missing", body = "missing" },
} })
assert(not invalid.ok and code_annotation.body == "code original")
for _, operation in ipairs({ "resolve", "remove" }) do
  invalid = dispatch(operation, { ids = { code_annotation.id, "missing" } })
  assert(not invalid.ok and code.state.get(code_annotation.id) == code_annotation)
  assert(code_annotation.status == "open")
end
assert(dispatch("update", { updates = { { id = code_annotation.id, body = "code updated" } } }).ok)
assert(code_annotation.body == "code updated")
assert(dispatch("resolve", { ids = { code_annotation.id } }).ok)
assert(code_annotation.status == "resolved")
unchanged_feedback()

-- Default discovery skips feedback and finds the visible code window in its tab.
local context = dispatch("context")
assert(context.current.file == file and context.session.id == code_session.id)
for _, payload in ipairs({ {}, { all = true }, { sessionId = code_session.id } }) do
  local listed = dispatch("list", payload)
  assert(listed.ok and #listed.comments == before_count)
  for _, annotation in ipairs(listed.comments) do
    assert(annotation.body ~= "feedback original" and annotation.body ~= "feedback only")
  end
end
assert(#dispatch("list", { sessionId = "feedback-only-session" }).comments == 0)
assert(dispatch("refresh").count == before_count)
assert(vim.wait(1000, function()
  if vim.fn.filereadable(state_path) ~= 1 then return false end
  local saved = vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
  for _, annotation in ipairs(saved.annotations) do
    if annotation.id == code_annotation.id then
      return annotation.body == "code updated" and annotation.status == "resolved"
    end
  end
  return false
end), "RPC mutations did not persist to ordinary state")
unchanged_feedback()

assert(dispatch("remove", { ids = { code_annotation.id } }).ok)
assert(not code.state.get(code_annotation.id))
assert(not dispatch("update", { updates = { { id = code_annotation.id, body = "must not find feedback" } } }).ok)
assert(not dispatch("resolve", { ids = { code_annotation.id } }).ok)
assert(not dispatch("remove", { ids = { code_annotation.id } }).ok)
assert(code.persistence.save_now())
local saved = vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
for _, annotation in ipairs(saved.annotations) do assert(annotation.id ~= code_annotation.id) end
unchanged_feedback()

-- With no visible code target, context/default list are empty, not feedback.
local code_win = vim.api.nvim_tabpage_list_wins(code_tab)[1]
vim.api.nvim_win_set_buf(code_win, vim.api.nvim_create_buf(false, true))
assert(vim.api.nvim_buf_is_loaded(code_buf))
context = dispatch("context")
assert(context.current == vim.NIL and context.session == vim.NIL)
assert(#dispatch("list").comments == 0)
assert(#dispatch("list", { all = true }).comments == before_count - 1)
assert(#dispatch("list", { sessionId = code_session.id }).comments == before_count - 1)
assert(dispatch("refresh").count == before_count - 1)
assert(dispatch("apply", { sessionId = code_session.id, comments = {
  comment("hidden-code", "explicit target without a visible code window"),
} }).ok)
assert(code.state.get("hidden-code").session_id == code_session.id)
assert(code.state.get("hidden-code").root == code_annotation.root)
unchanged_feedback()
