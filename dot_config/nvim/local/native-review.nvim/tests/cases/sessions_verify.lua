local file = assert(vim.env.NATIVE_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local review = require("native_review")
local store = require("native_review.sessions")
local workspace = require("native_review.scope").current()
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
assert(review.session_switch(archived.id))
assert(store.get(archived.id).status == "active")
payload = assert(review.payload())
assert(payload:find("first pass", 1, true) and not payload:find("second pass", 1, true))
