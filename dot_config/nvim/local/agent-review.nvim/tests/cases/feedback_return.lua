local review = require("agent_review")
local reader = require("agent_review.feedback_reader")
local root = assert(vim.env.AGENT_REVIEW_TEST_TMP)
local directory = root .. "/conversation"
local message = directory .. "/reply"
vim.fn.mkdir(message, "p")
local function write(path, value)
  vim.fn.writefile({ vim.json.encode(value) }, path)
end
local source = message .. "/source.md"
local metadata = message .. "/metadata.json"
local state = message .. "/annotations.json"
local catalogue = directory .. "/catalogue.json"
vim.fn.writefile({ "# Response", "A response worth reviewing", "last line" }, source)
write(metadata, { schemaVersion = 1, reader = true, piSessionId = "conversation",
  assistantMessageId = "reply", feedbackDirectory = message, sourcePath = source,
  feedbackPath = message .. "/feedback.json" })
write(catalogue, { schemaVersion = 1, piSessionId = "conversation", latestEntryId = "reply",
  messages = { { entryId = "reply", title = "Response", prompt = "Question", timestamp = "2026-11-03",
    onBranch = true, finished = true, sourcePath = source, metadataPath = metadata, feedbackStatePath = state } } })
local function remote(action)
  local result = reader.remote({ action = action, cataloguePath = catalogue })
  assert(result.ok, result.error)
  assert(result.open, "reader should retain its draft while viewing code")
end

vim.cmd("edit " .. vim.fn.fnameescape(vim.env.AGENT_REVIEW_TEST_FILE))
local code = vim.api.nvim_get_current_buf()
local code_tab = vim.api.nvim_get_current_tabpage()
local code_note = assert(review.annotation.add({ body = "Code draft" }))
remote("open")
local response = vim.api.nvim_get_current_buf()
local response_tab = vim.api.nvim_get_current_tabpage()
local response_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local draft = assert(review.annotation.add({ body = "Response draft" }))
vim.fn.winrestview({ lnum = 2, col = 0, topline = 2 })
vim.cmd("buffer " .. code)
assert(vim.api.nvim_get_current_buf() == code)
assert(review.annotation.get(code_note.id).body == "Code draft")
remote("status") -- Must not switch a buffer as a side effect.
assert(vim.api.nvim_get_current_buf() == code)
remote("focus") -- Same RPC used by /feedback after the reader is already open.
assert(vim.api.nvim_get_current_buf() == response, "/feedback focused the editor but did not restore the response buffer")
assert(vim.api.nvim_get_current_tabpage() == response_tab)
assert(vim.api.nvim_get_current_win() == response_win)
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "return must retain the response cursor")
assert(review.annotation.get(draft.id).body == "Response draft")
assert(vim.bo[response].buflisted, "response must be discoverable in ordinary buffer navigation")
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  assert(not (vim.bo[buf].buflisted and vim.api.nvim_buf_get_name(buf) == ""),
    "opening feedback left a listed empty placeholder instead of the response")
end

-- Standard buffer navigation, without invoking the reader's RPC.
vim.cmd("buffer " .. code)
vim.cmd("bnext")
assert(vim.api.nvim_get_current_buf() == response, "ordinary :bnext could not return to the response")
assert(not vim.bo.modifiable and vim.bo.readonly, "listing must not make snapshots editable")
assert(review.annotation.get(draft.id).body == "Response draft")

-- Restore into a visible response split rather than replacing a code split.
vim.cmd("split")
local response_split = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(response_win)
vim.cmd("buffer " .. code)
remote("focus")
assert(vim.api.nvim_get_current_win() == response_split, "focus should prefer a split already showing the response")
assert(vim.api.nvim_win_get_buf(response_win) == code, "focus replaced an unrelated code split")
assert(review.annotation.get(draft.id).body == "Response draft")

assert(require("agent_review.feedback").keep())
vim.api.nvim_set_current_tabpage(code_tab)
assert(review.annotation.get(code_note.id).body == "Code draft")

-- The dedicated launcher also starts with an empty placeholder. Its legacy
-- pane handle ultimately uses the same focus RPC after terminal verification.
local dedicated = directory .. "/dedicated.json"
vim.fn.writefile(vim.fn.readfile(catalogue), dedicated)
local previous_catalogue = vim.env.PI_FEEDBACK_CATALOG
vim.env.PI_FEEDBACK_CATALOG = dedicated
vim.cmd("enew")
local placeholder = vim.api.nvim_get_current_buf()
assert(reader.open({ catalog_path = dedicated }))
assert(not vim.api.nvim_buf_is_valid(placeholder), "dedicated reader left its empty startup buffer listed")
assert(vim.api.nvim_get_current_buf() == response)
vim.cmd("buffer " .. code)
local focused = reader.remote({ action = "focus", cataloguePath = dedicated })
assert(focused.ok and focused.open, focused.error)
assert(vim.api.nvim_get_current_buf() == response, "dedicated reader did not restore the response")
assert(review.annotation.get(draft.id).body == "Response draft")
reader.close()
vim.env.PI_FEEDBACK_CATALOG = previous_catalogue
