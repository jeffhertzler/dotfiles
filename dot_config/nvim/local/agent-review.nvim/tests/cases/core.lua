local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))

local review = require("agent_review")
assert(review.add == nil and review.annotation and review.session and review.ui)
assert(vim.fn.exists(":AgentReview") == 2)
assert(vim.fn.exists(":AgentReviewAdd") == 0)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local annotation = assert(review.annotation.add({ body = "core note" }))
assert(annotation.target.side == "working")
assert(annotation.target.start_line == 2)
assert(annotation.session_id)
local public_copy = review.annotation.get(annotation.id)
public_copy.body = "must not mutate state"
assert(review.annotation.get(annotation.id).body == "core note")
assert(vim.bo.modifiable)

assert(review.annotation.edit(annotation.id, { body = "edited note" }))
assert(review.annotation.get(annotation.id).body == "edited note")
assert(review.annotation.resolve(annotation.id))
assert(review.annotation.get(annotation.id).status == "resolved")
assert(review.annotation.reopen(annotation.id))
assert(review.annotation.get(annotation.id).status == "open")

local namespace = vim.api.nvim_get_namespaces().agent_review_render
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) >= 3)
assert(review.annotation.remove(annotation.id))
assert(#review.annotation.list({ all = true }) == 0)
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 0)
