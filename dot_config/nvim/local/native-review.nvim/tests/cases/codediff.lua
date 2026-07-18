local directory = assert(vim.env.NATIVE_REVIEW_TEST_TMP)
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
local review = require("native_review")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local working = assert(review.add({ body = "working note" }))
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
local namespace = vim.api.nvim_get_namespaces().native_review_render
assert(#vim.api.nvim_buf_get_extmarks(modified_buf, namespace, 0, -1, {}) >= 3)

vim.api.nvim_set_current_win(original_win)
local old = assert(review.add({ body = "old revision note" }))
assert(old.target.side == "old")
assert(#vim.api.nvim_buf_get_extmarks(original_buf, namespace, 0, -1, {}) >= 3)
assert(vim.bo[modified_buf].modifiable)
