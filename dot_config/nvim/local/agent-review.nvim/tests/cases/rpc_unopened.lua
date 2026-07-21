local directory = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(directory, "p")
local current = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(current))

local target = directory .. "/unopened.lua"
vim.fn.writefile({ "first", "anchor me", "last" }, target)
assert(vim.fn.bufnr(target) == -1)

local result = require("agent_review.rpc").apply({
  schemaVersion = 1,
  author = "test-agent",
  comments = {
    {
      id = "unopened-finding",
      body = "anchored before opening",
      target = { file = target, side = "working", startLine = 2, endLine = 2 },
    },
  },
})
assert(result.ok and result.count == 1)
local annotation = assert(require("agent_review.state").get("unopened-finding"))
assert(annotation.anchor and annotation.anchor.selected[1] == "anchor me")
assert(vim.fn.bufnr(target) == -1, "temporary anchor buffer should not remain loaded")
