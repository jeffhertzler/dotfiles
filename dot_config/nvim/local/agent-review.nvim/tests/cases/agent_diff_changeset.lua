local root = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(root, "p")
local function git(...)
  local result = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end

git("init", "-q")
git("config", "user.email", "test@example.com")
git("config", "user.name", "Test")
vim.fn.writefile({ "first old", "shared" }, root .. "/first.txt")
vim.fn.writefile({ "second old", "shared" }, root .. "/second.txt")
git("add", ".")
git("commit", "-qm", "base")
vim.fn.writefile({ "first new", "shared", "added" }, root .. "/first.txt")
vim.fn.writefile({ "second new", "shared", "added" }, root .. "/second.txt")
git("add", ".")
git("commit", "-qm", "target")

local diff = require("agent_diff")
diff.setup({ initial_timeout_ms = 100, live_timeout_ms = 50 })
local files = {
  { path = "first.txt", status = "M" },
  { path = "second.txt", status = "M" },
}
local function open()
  diff.open_changeset({
    root = root,
    files = files,
    original_revision = "HEAD^",
    modified_revision = "HEAD",
    layout = "side-by-side",
    explorer = true,
  })
  assert(vim.wait(10000, function()
    local session = diff.get_session()
    local context = session and session.modified_buf and vim.b[session.modified_buf].agent_diff_context
    return session and session.original_win and context and context.path == "first.txt" and session.index == 1
  end, 20), "multi-file changeset did not open")
  return assert(diff.get_session())
end

local session = open()
local review = require("agent_review")
vim.api.nvim_set_current_win(session.modified_win)
vim.api.nvim_win_set_cursor(session.modified_win, { 1, 0 })
local new_annotation = assert(review.annotation.add({ body = "new-side comment" }))
assert(new_annotation.host == "agent_diff")
assert(new_annotation.target.side == "new")
assert(new_annotation.target.file:find("first.txt", 1, true))

local first_modified_buf = session.modified_buf
diff.next_file()
assert(vim.wait(10000, function()
  local context = session.modified_buf and vim.b[session.modified_buf].agent_diff_context
  return session.index == 2 and session.modified_buf ~= first_modified_buf and context and context.path == "second.txt"
end, 20), "second changeset file did not open")
vim.api.nvim_set_current_win(session.original_win)
vim.api.nvim_win_set_cursor(session.original_win, { 1, 0 })
local old_annotation = assert(review.annotation.add({ body = "old-side comment" }))
assert(old_annotation.host == "agent_diff")
assert(old_annotation.target.side == "old")
assert(old_annotation.target.file:find("second.txt", 1, true))

-- Navigate away and back: each side must recover its annotations from durable
-- targets rather than retaining buffer-local marks from the previous file.
diff.prev_file()
assert(vim.wait(10000, function()
  local context = session.modified_buf and vim.b[session.modified_buf].agent_diff_context
  return session.index == 1 and context and context.path == "first.txt"
end, 20))
require("agent_review.render").refresh_visible()
local namespace = vim.api.nvim_create_namespace("agent_review_render")
assert(#vim.api.nvim_buf_get_extmarks(session.modified_buf, namespace, 0, -1, {}) > 0)
diff.next_file()
assert(vim.wait(10000, function()
  local context = session.modified_buf and vim.b[session.modified_buf].agent_diff_context
  return session.index == 2 and context and context.path == "second.txt"
end, 20))
require("agent_review.render").refresh_visible()
assert(#vim.api.nvim_buf_get_extmarks(session.original_buf, namespace, 0, -1, {}) > 0)

-- Closing and reopening recreates every diff buffer. The comments must still
-- bind to the correct file and side.
diff.close()
assert(diff.get_session() == nil)
session = open()
require("agent_review.render").refresh_visible()
assert(#vim.api.nvim_buf_get_extmarks(session.modified_buf, namespace, 0, -1, {}) > 0)
diff.next_file()
assert(vim.wait(10000, function()
  local context = session.original_buf and vim.b[session.original_buf].agent_diff_context
  return session.index == 2 and context and context.path == "second.txt"
end, 20))
require("agent_review.render").refresh_visible()
assert(#vim.api.nvim_buf_get_extmarks(session.original_buf, namespace, 0, -1, {}) > 0)

local annotations = review.annotation.list({ all = true })
assert(#annotations == 2)
assert(annotations[1].target.side ~= annotations[2].target.side)
diff.close()
print("PASS agent_diff_changeset.lua")
