local directory = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(directory, "p")
assert(vim.system({ "git", "init", "-q", directory }):wait().code == 0)
vim.system({ "git", "-C", directory, "config", "user.email", "test@example.com" }):wait()
vim.system({ "git", "-C", directory, "config", "user.name", "Test" }):wait()
local file = directory .. "/sample.lua"
vim.fn.writefile({ "local value = 1", "return value" }, file)
vim.system({ "git", "-C", directory, "add", "sample.lua" }):wait()
assert(vim.system({ "git", "-C", directory, "commit", "-qm", "initial" }):wait().code == 0)
vim.fn.writefile({ "local value = 2", "local other = value + 1", "return other" }, file)

vim.cmd("cd " .. vim.fn.fnameescape(directory))
vim.cmd("edit " .. vim.fn.fnameescape(file))
local review = require("agent_review")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local working = assert(review.annotation.add({ body = "working note" }))
assert(working.target.side == "working")

vim.cmd("CodeDiff file HEAD")
local lifecycle = require("codediff.ui.lifecycle")
local tabpage
assert(vim.wait(5000, function()
  for candidate, session in pairs(require("codediff.ui.lifecycle.session").get_active_diffs()) do
    if session and session.stored_diff_result then
      tabpage = candidate
      return true
    end
  end
  return false
end, 20), "CodeDiff session did not become ready")
vim.api.nvim_set_current_tabpage(tabpage)
local original_buf, modified_buf = lifecycle.get_buffers(tabpage)
local original_win = lifecycle.get_windows(tabpage)
review.refresh(tabpage)
local namespace = vim.api.nvim_get_namespaces().agent_review_render
assert(#vim.api.nvim_buf_get_extmarks(modified_buf, namespace, 0, -1, {}) >= 3)

vim.api.nvim_set_current_win(original_win)
local old = assert(review.annotation.add({ body = "old revision note" }))
assert(old.target.side == "old")
assert(#vim.api.nvim_buf_get_extmarks(original_buf, namespace, 0, -1, {}) >= 3)
assert(vim.bo[modified_buf].modifiable)

assert(require("codediff.ui.view.toggle").toggle(tabpage))
assert(vim.wait(5000, function()
  local current = lifecycle.get_session(tabpage)
  return current and lifecycle.get_layout(tabpage) == "inline" and current.stored_diff_result ~= nil
end, 20), "inline toggle did not finish")
original_buf, modified_buf = lifecycle.get_buffers(tabpage)
review.refresh(tabpage)

local found_old_box = false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(modified_buf, namespace, 0, -1, { details = true })) do
  for _, virtual_line in ipairs(mark[4].virt_lines or {}) do
    for _, chunk in ipairs(virtual_line) do
      if chunk[1]:find("OLD", 1, true) then
        found_old_box = true
      end
    end
  end
end
assert(found_old_box, "old-side annotation was not rendered in inline layout")

local session = lifecycle.get_session(tabpage)
local change = assert(session.stored_diff_result.changes[1])
local modified_count = vim.api.nvim_buf_line_count(modified_buf)
local cursor_line = math.max(1, math.min(change.modified.start_line, modified_count))
local modified_win = select(2, lifecycle.get_windows(tabpage))
vim.api.nvim_set_current_win(modified_win)
vim.api.nvim_win_set_cursor(modified_win, { cursor_line, 0 })
local candidates = require("agent_review.codediff").old_lines_at_cursor(tabpage, cursor_line)
assert(#candidates > 0)
local capture = assert(require("agent_review.codediff").capture_old_line(tabpage, candidates[1].line))
assert(capture.target.side == "old" and capture.anchor.selected[1] ~= nil)
assert(vim.fn.exists(":AgentReview") == 2)
assert(vim.fn.exists(":AgentReviewAddOld") == 0)
