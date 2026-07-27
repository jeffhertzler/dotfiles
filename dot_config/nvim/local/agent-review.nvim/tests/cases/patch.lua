local tmp = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(tmp, "p")
local function git(...)
  local result = vim.system({ "git", "-C", tmp, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end

git("init", "-q")
git("config", "user.email", "test@example.com")
git("config", "user.name", "Test")
local path = tmp .. "/review.lua"
vim.fn.writefile({ "deleted line", "keep" }, path)
git("add", "review.lua")
git("commit", "-qm", "initial")
vim.fn.writefile({ "added line", "keep" }, path)
vim.cmd.edit(vim.fn.fnameescape(path))

local patch = require("agent_diff.patch")
local workspace = assert(patch.open())
assert(vim.wait(5000, function()
  return workspace.sections[1] and #workspace.sections[1].hunks > 0
end, 10), "patch did not load")
local pane = assert(workspace.panes.unstaged)
local deleted_row, added_row
for row, metadata in pairs(pane.rows) do
  if metadata.section == "unstaged" and metadata.kind == "delete" and metadata.text == "deleted line" then
    deleted_row = row
  elseif metadata.section == "unstaged" and metadata.kind == "add" and metadata.text == "added line" then
    added_row = row
  end
end
assert(deleted_row and added_row)

local review = require("agent_review")
vim.api.nvim_set_current_win(pane.win)
vim.api.nvim_win_set_cursor(pane.win, { deleted_row, 0 })
local deleted = assert(review.annotation.add({ body = "exact deleted review" }))
assert(deleted.host == "agent_patch")
assert(deleted.target.side == "old" and deleted.target.start_line == 1)
assert(deleted.revision.selected_expression == "INDEX")

vim.api.nvim_win_set_cursor(pane.win, { added_row, 0 })
local added = assert(review.annotation.add({ body = "exact working review" }))
assert(added.target.side == "working" and added.target.start_line == 1)
assert(added.revision.selected_expression == "WORKING")

require("agent_review.patch").render(workspace)
local namespace = vim.api.nvim_get_namespaces().agent_review_patch
assert(namespace and #vim.api.nvim_buf_get_extmarks(pane.buf, namespace, 0, -1, {}) == 2)
patch.close()
print("PASS patch.lua")
