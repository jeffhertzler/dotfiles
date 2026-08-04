local file = assert(vim.env.AGENT_BRIDGE_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 2, 0 })

local origin_win = vim.api.nvim_get_current_win()
local origin_cursor = vim.api.nvim_win_get_cursor(origin_win)
local accepted
local input = require("agent_bridge.input").new({
  title = " Test input ",
  footer = " Ctrl-S accept · q cancel ",
  width = 0.5,
  min_width = 48,
  min_height = 1,
  max_height = 3,
  persistent = false,
  ctrl_s = { action = "save" },
  on_accept = function(value, action, done)
    accepted = { value = value, action = action }
    done(true)
  end,
})
input:open("")

assert(input.buffer and vim.api.nvim_buf_is_valid(input.buffer))
assert(vim.bo[input.buffer].filetype == "markdown")
local config = vim.api.nvim_win_get_config(input.window.win)
assert(config.border and #config.border > 0 and config.footer)
assert(config.width >= 48 and config.height == 1)
local winhighlight = vim.wo[input.window.win].winhighlight
assert(winhighlight:find("FloatBorder:SnacksInputBorder", 1, true))
assert(winhighlight:find("FloatTitle:SnacksInputTitle", 1, true))
assert(input.origin_win == origin_win and input.origin_insert_mode == false)

local normal_escape = false
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(input.buffer, "n")) do
  normal_escape = normal_escape or mapping.lhs == "<Esc>"
end
assert(normal_escape, "normal Escape must close the input")
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(input.buffer, "i")) do
  assert(mapping.lhs ~= "<Esc>", "insert Escape must leave insert mode")
end

vim.api.nvim_buf_set_lines(input.buffer, 0, -1, false, { string.rep("wrapped input ", 20) })
input:_resize()
config = vim.api.nvim_win_get_config(input.window.win)
assert(config.height > 1, "wrapped input must grow the window")
assert(config.height <= input.opts.max_height, "wrapped input must respect max_height")

vim.api.nvim_buf_set_lines(input.buffer, 0, -1, false, { "autocomplete" })
input:_resize()
local plain_height = vim.api.nvim_win_get_config(input.window.win).height
local completion_ns = vim.api.nvim_create_namespace("AgentBridgeInputCompletionTest")
vim.api.nvim_buf_set_extmark(input.buffer, completion_ns, 0, 4, {
  virt_text = { { string.rep(" ghost text", 20), "Comment" } },
  virt_text_pos = "inline",
  virt_lines = { { { "multiline completion", "Comment" } } },
})
input:_resize()
config = vim.api.nvim_win_get_config(input.window.win)
assert(config.height == plain_height, "completion decorations must not resize the input")
vim.api.nvim_buf_clear_namespace(input.buffer, completion_ns, 0, -1)

vim.api.nvim_buf_set_lines(input.buffer, 0, -1, false, { "first line", "second line" })
input:_resize()
assert(vim.wo[input.window.win].cursorline)
input:_accept({ action = "save" })
assert(accepted.value == "first line\nsecond line" and accepted.action.action == "save")
assert(not vim.api.nvim_buf_is_valid(input.buffer or -1))
assert(vim.wait(1000, function()
  return vim.api.nvim_get_current_win() == origin_win and vim.api.nvim_get_mode().mode:sub(1, 1) == "n"
end, 10), "closing input did not restore normal mode")
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(origin_win), origin_cursor))

local cancelled = require("agent_bridge.input").new({ persistent = false })
cancelled:open("cancel me")
vim.cmd("stopinsert")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
assert(vim.wait(1000, function()
  return not vim.api.nvim_buf_is_valid(cancelled.buffer or -1)
end, 10), "normal Escape did not close the input")
