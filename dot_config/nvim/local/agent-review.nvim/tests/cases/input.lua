local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })

local review = require("agent_review")
local origin_win = vim.api.nvim_get_current_win()
local origin_cursor = vim.api.nvim_win_get_cursor(origin_win)
local input = assert(review.annotation.add())
assert(input.buffer and vim.api.nvim_buf_is_valid(input.buffer))
assert(vim.bo[input.buffer].filetype == "markdown")
local window_config = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
assert(window_config.border and #window_config.border > 0 and window_config.footer)
assert(window_config.width >= 48)
local winhighlight = vim.wo[vim.api.nvim_get_current_win()].winhighlight
assert(winhighlight:find("FloatBorder:SnacksInputBorder", 1, true))
assert(winhighlight:find("FloatTitle:SnacksInputTitle", 1, true))
assert(not vim.wo[vim.api.nvim_get_current_win()].cursorline)
assert(#vim.api.nvim_buf_get_keymap(input.buffer, "i") > 0)
assert(input.origin_win == origin_win and input.origin_insert_mode == false)
local normal_escape = false
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(input.buffer, "n")) do
  normal_escape = normal_escape or mapping.lhs == "<Esc>"
end
assert(normal_escape, "normal Escape must close the input")
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(input.buffer, "i")) do
  assert(mapping.lhs ~= "<Esc>", "escape must leave insert mode instead of closing the input")
end

vim.api.nvim_buf_set_lines(input.buffer, 0, -1, false, { "first line", "second line" })
input:_resize()
assert(vim.wo[vim.api.nvim_get_current_win()].cursorline)
input:_accept({ action = "save" })
local annotations = review.annotation.list({ all = true })
assert(#annotations == 1 and annotations[1].body == "first line\nsecond line")
assert(not vim.api.nvim_buf_is_valid(input.buffer or -1))
assert(vim.wait(1000, function()
  return vim.api.nvim_get_current_win() == origin_win and vim.api.nvim_get_mode().mode:sub(1, 1) == "n"
end, 10), "closing review input did not restore normal mode")
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(origin_win), origin_cursor))

local editor = assert(review.annotation.edit(annotations[1].id))
vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { "edited", "multiline" })
editor:_accept({ action = "save" })
assert(review.annotation.get(annotations[1].id).body == "edited\nmultiline")

local cancelled = assert(review.annotation.add())
vim.cmd("stopinsert")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
assert(vim.wait(1000, function()
  return not vim.api.nvim_buf_is_valid(cancelled.buffer or -1)
end, 10), "normal Escape did not close the input")
assert(#review.annotation.list({ all = true }) == 1)
