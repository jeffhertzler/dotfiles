local file = assert(vim.env.NATIVE_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local review = require("native_review")
review.refresh()
local moving, stale = unpack(review.annotations())
assert(moving.id == "review-1" and moving.target.start_line == 3)
assert(moving.freshness == "reanchored")
assert(stale.id == "review-2" and stale.target.start_line == 4)
assert(stale.freshness == "stale")

local payload = assert(review.payload())
assert(payload:find("review%-1") and not payload:find("review%-2"))
local namespace = vim.api.nvim_get_namespaces().native_review_render
local found_stale = false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
  if mark[4].sign_hl_group == "NativeReviewStale" then
    found_stale = true
  end
end
assert(found_stale)
