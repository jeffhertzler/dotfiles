local root = vim.fs.dirname(vim.env.AGENT_REVIEW_TEST_FILE) .. "/reader-artifacts"
local document = vim.json.decode(table.concat(vim.fn.readfile(root .. "/catalogue.json"), "\n"))
local first = document.messages[2]
local reader = require("agent_review.feedback_reader")
assert(reader.open({ catalog_path = root .. "/catalogue.json", feedback_state_path = first.feedbackStatePath }))
assert(vim.api.nvim_buf_get_name(0) == first.sourcePath)
assert(require("agent_review").annotation.list()[1].body == "first draft")
assert(vim.fn.filereadable(vim.fs.dirname(first.sourcePath) .. "/feedback.json") == 0)
assert(reader.select("reply-2"))
assert(#require("agent_review").annotation.list({ all = true }) == 0)
assert(vim.fn.filereadable(document.messages[3].sourcePath) == 1)
reader.close()
