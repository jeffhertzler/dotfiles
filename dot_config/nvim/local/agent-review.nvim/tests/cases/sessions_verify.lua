local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local review = require("agent_review")
local store = require("agent_review.sessions")
local workspace = require("agent_review.scope").current()
local available = store.list(workspace, { include_archived = true })
assert(#available == 2)

local archived, active
for _, session in ipairs(available) do
  if session.status == "archived" then archived = session else active = session end
end
assert(archived and active and active.name == "Second pass")
assert(store.current().id == active.id)
local payload = assert(review.payload())
assert(payload:find("second pass", 1, true) and not payload:find("first pass", 1, true))
local current_wire = require("agent_review.rpc").list()
assert(#current_wire.comments == 1 and current_wire.comments[1].body == "second pass")
assert(#require("agent_review.rpc").list({ all = true }).comments == 2)
assert(review.session.activate(archived.id))
assert(store.get(archived.id).status == "active")
payload = assert(review.payload())
assert(payload:find("first pass", 1, true) and not payload:find("second pass", 1, true))
