local file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local review = require("agent_review")
local annotations = review.annotation.list({ all = true })
assert(#annotations == 2)
assert(annotations[1].id == "review-1" and annotations[1].status == "resolved")
assert(annotations[2].id == "persistent-agent" and annotations[2].author.kind == "agent")
assert(annotations[1].session_id == annotations[2].session_id)

local sessions = require("agent_review.sessions").list(nil, { include_archived = true })
assert(#sessions == 1)
local document = vim.json.decode(table.concat(vim.fn.readfile(vim.env.NVIM_AGENT_REVIEW_STATE), "\n"))
assert(document.schemaVersion == 2)
assert(#document.sessions == 1 and document.annotations[1].sessionId)

review.refresh()
local namespace = vim.api.nvim_get_namespaces().agent_review_render
assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) >= 6)
