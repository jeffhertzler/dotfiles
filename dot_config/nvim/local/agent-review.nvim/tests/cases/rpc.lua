local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))

local rpc = require("agent_review.rpc")
local review = require("agent_review")
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
assert(review.annotation.list({ all = true })[1].author.kind == "agent")
assert(review.annotation.list({ all = true })[1].session_id)

local before = #review.annotation.list({ all = true })
local invalid = rpc.update({ updates = {
  { id = "agent-one", body = "must not apply" },
  { id = "missing", status = "resolved" },
} })
assert(not invalid.ok and #review.annotation.list({ all = true }) == before)
assert(review.annotation.list({ all = true })[1].body == "agent finding")

assert(rpc.update({ updates = { { id = "agent-one", body = "updated" } } }).ok)
assert(rpc.resolve({ ids = { "agent-one" } }).ok)
assert(require("agent_review.state").get("agent-one").status == "resolved")
assert(rpc.remove({ ids = { "agent-one", "agent-two" } }).ok)
assert(#review.annotation.list({ all = true }) == 0)
