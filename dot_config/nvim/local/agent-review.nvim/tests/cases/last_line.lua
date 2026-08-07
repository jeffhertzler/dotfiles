local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
vim.cmd("normal! G")

local initial_topline = vim.fn.winsaveview().topline
local annotation = assert(require("agent_review").annotation.add({ body = "visible at end of file" }))
assert(annotation.target.start_line == 80 and annotation.target.end_line == 80)

local namespace = vim.api.nvim_get_namespaces().agent_review_render
local box_height
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
  local details = mark[4]
  if details.virt_lines then
    box_height = #details.virt_lines
    break
  end
end
assert(box_height and box_height > 0)
assert(vim.fn.winsaveview().topline > initial_topline)
assert(vim.fn.winline() + box_height <= vim.api.nvim_win_get_height(0))
