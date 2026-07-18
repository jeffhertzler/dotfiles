local file = assert(vim.env.NATIVE_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))

local rpc = require("native_review.rpc")
local review = require("native_review")
local applied = rpc.apply({
  schemaVersion = 1,
  author = "test-agent",
  comments = {
    {
      id = "agent-one",
      body = "agent finding",
      kind = "issue",
      target = { file = file, side = "working", startLine = 2, endLine = 2 },
    },
    {
      id = "agent-two",
      body = "second finding",
      target = { file = file, side = "working", startLine = 3, endLine = 3 },
    },
  },
})
assert(applied.ok and applied.count == 2)
assert(review.annotations()[1].author.kind == "agent")
assert(review.annotations()[1].session_id)

local before = #review.annotations()
local invalid = rpc.update({ updates = {
  { id = "agent-one", body = "must not apply" },
  { id = "missing", status = "resolved" },
} })
assert(not invalid.ok and #review.annotations() == before)
assert(review.annotations()[1].body == "agent finding")

assert(rpc.update({ updates = { { id = "agent-one", body = "updated" } } }).ok)
assert(rpc.resolve({ ids = { "agent-one" } }).ok)
assert(require("native_review.state").get("agent-one").status == "resolved")
assert(rpc.remove({ ids = { "agent-one", "agent-two" } }).ok)
assert(#review.annotations() == 0)
