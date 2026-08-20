local source_file = assert(vim.env.AGENT_REVIEW_TEST_FILE)
local tmp = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(tmp, "p")
local source_path = tmp .. "/source.md"
vim.fn.writefile(vim.fn.readfile(source_file), source_path)
vim.cmd("edit " .. vim.fn.fnameescape(source_path))

local feedback_path = tmp .. "/feedback.json"
local metadata_path = tmp .. "/metadata.json"
vim.fn.writefile({ vim.json.encode({
  schemaVersion = 1,
  piSessionId = "pi-session-test",
  assistantMessageId = "assistant-entry-test",
  feedbackDirectory = tmp,
  sourcePath = source_path,
  feedbackPath = feedback_path,
}) }, metadata_path)

local feedback_adapter = require("agent_review.feedback")
assert(feedback_adapter.attach({ metadata_path = metadata_path }))
assert(vim.bo.filetype == "markdown")
assert(not vim.bo.modifiable and vim.bo.readonly and not vim.bo.swapfile)
assert(type(vim.b.pi_feedback) == "table")
assert(vim.b.pi_feedback_disable_lint == true)
assert(not vim.diagnostic.is_enabled({ bufnr = 0 }))
assert(vim.fn.maparg("<leader>rs", "n") ~= "")
assert(vim.fn.maparg("<leader>rk", "n") ~= "")

vim.api.nvim_win_set_cursor(0, { 3, 0 })
local annotation = assert(require("agent_review").annotation.add({ body = "Explain this claim more precisely." }))
assert(feedback_adapter.submit({ quit = false }))
assert(vim.fn.filereadable(feedback_path) == 1)

local feedback = vim.json.decode(table.concat(vim.fn.readfile(feedback_path), "\n"))
assert(feedback.schemaVersion == 1)
assert(feedback.piSessionId == "pi-session-test")
assert(feedback.assistantMessageId == "assistant-entry-test")
assert(#feedback.comments == 1)
local comment = feedback.comments[1]
assert(annotation.id:match("^review%-"))
assert(comment.id == "feedback-1")
assert(comment.body == "Explain this claim more precisely.")
assert(comment.startLine == 3 and comment.endLine == 3)
assert(comment.selection == "line")
assert(vim.deep_equal(comment.quotedText, { "target line" }))

assert(feedback_adapter.keep({ quit = false }))
assert(vim.fn.isdirectory(tmp) == 1)
assert(feedback_adapter.discard({ quit = false }))
assert(vim.fn.isdirectory(tmp) == 0)
