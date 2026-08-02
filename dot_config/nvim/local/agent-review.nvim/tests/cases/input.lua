local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })

local review = require("agent_review")
local input = assert(review.annotation.add())
assert(input.buffer and vim.api.nvim_buf_is_valid(input.buffer))
assert(input.opts.persistent == false and input.opts.min_height == 1 and input.opts.max_height == 8)

local window_config = vim.api.nvim_win_get_config(input.window.win)
assert(window_config.footer, "review input must show save and cancel controls")
assert(window_config.width >= 48, "review input must enforce its compact minimum width")

vim.api.nvim_buf_set_lines(input.buffer, 0, -1, false, { "first line", "second line" })
input:_accept({ action = "save" })
local annotations = review.annotation.list({ all = true })
assert(#annotations == 1 and annotations[1].body == "first line\nsecond line")
assert(not vim.api.nvim_buf_is_valid(input.buffer or -1))

local editor = assert(review.annotation.edit(annotations[1].id))
vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { "edited", "multiline" })
editor:_accept({ action = "save" })
assert(review.annotation.get(annotations[1].id).body == "edited\nmultiline")

local cancelled = assert(review.annotation.add())
cancelled:close()
assert(#review.annotation.list({ all = true }) == 1)
