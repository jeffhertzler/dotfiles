local file = assert(vim.env.NATIVE_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local review = require("native_review")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local human = assert(review.add({ body = "persistent human" }))
assert(human.id == "review-1")

local imported = require("native_review.rpc").apply({
  author = "test-agent",
  comments = {
    { id = "persistent-agent", body = "persistent agent", target = { file = file, startLine = 3 } },
  },
})
assert(imported.ok)
assert(require("native_review.rpc").resolve({ ids = { human.id } }).ok)
local ok, err = require("native_review.persistence").save_now()
assert(ok, err)
