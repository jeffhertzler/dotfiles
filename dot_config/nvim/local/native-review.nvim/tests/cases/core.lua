local file = assert(vim.env.NATIVE_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))

local review = require("native_review")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local annotation = assert(review.add({ body = "core note" }))
assert(annotation.target.side == "working")
assert(annotation.target.start_line == 2)
assert(annotation.session_id)
assert(vim.bo.modifiable)

assert(review.edit(annotation.id, { body = "edited note" }))
assert(annotation.body == "edited note")
assert(review.resolve(annotation.id))
assert(annotation.status == "resolved")
assert(review.reopen(annotation.id))
assert(annotation.status == "open")

local namespace = vim.api.nvim_get_namespaces().native_review_render
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) >= 3)
assert(review.remove(annotation.id))
assert(#review.annotations() == 0)
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 0)
