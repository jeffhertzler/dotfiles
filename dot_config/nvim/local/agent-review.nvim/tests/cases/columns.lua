local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 6 })
vim.cmd("normal! v4l")
assert(vim.fn.mode(1):sub(1, 1) == "v")

local annotation = assert(require("agent_review").annotation.add({
  visual = true,
  body = "column note",
}))
assert(annotation.target.selection == "character")
assert(annotation.target.start_line == 2 and annotation.target.end_line == 2)
assert(annotation.target.start_col == 7 and annotation.target.end_col == 11)
