local root = vim.fs.dirname(vim.env.AGENT_REVIEW_TEST_FILE) .. "/reader-artifacts"
vim.fn.mkdir(root, "p")
local function write(path, value)
  vim.fn.writefile({ vim.json.encode(value) }, path)
end
local function message(id, on_branch, finished)
  -- Directory names need not be entry IDs. In particular, IDs are not paths.
  local directory = root .. "/snapshot-" .. tostring(#vim.fn.glob(root .. "/snapshot-*", false, true) + 1)
  vim.fn.mkdir(directory, "p")
  local entry = {
    entryId = id,
    title = "Reply " .. id,
    prompt = "user prompt " .. id,
    timestamp = "2026-07-01T12:00:00Z",
    onBranch = on_branch,
    finished = finished,
    sourcePath = directory .. "/source.md",
    metadataPath = directory .. "/metadata.json",
    feedbackStatePath = directory .. "/annotations.json",
  }
  vim.fn.writefile({ "# " .. id, "", "search-only-token-" .. id, "tail" }, entry.sourcePath)
  write(entry.metadataPath, {
    schemaVersion = 1,
    piSessionId = "reader-session",
    assistantMessageId = id,
    reader = true,
    feedbackDirectory = directory,
    sourcePath = entry.sourcePath,
    feedbackPath = directory .. "/feedback.json",
  })
  return entry
end
local document = { schemaVersion = 1, piSessionId = "reader-session", latestEntryId = "../opaque", messages = {} }
for i = 1, 23 do
  document.messages[i] = message(i == 1 and "../opaque" or "reply-" .. i, true, true)
end
local first, second = document.messages[1], document.messages[2]
document.messages[24] = message("progress", true, false)
document.messages[25] = message("other-branch", false, true)
local path = root .. "/catalogue.json"
write(path, document)
vim.env.PI_FEEDBACK_CATALOG = path

local reader = require("agent_review.feedback_reader")
local review = require("agent_review")
local feedback = require("agent_review.feedback")
assert(not reader.open({ catalog_path = root .. "/missing.json" }))
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "# Pi feedback reader could not open")
assert(vim.fn.maparg("q", "n", false, true).buffer ~= 1)
assert(vim.fn.maparg("<leader>rml", "n", false, true).buffer == 1)
assert(reader.open())
assert(vim.api.nvim_buf_get_name(0) == first.sourcePath)
local first_buf = vim.api.nvim_get_current_buf()
assert(#reader.visible_messages() == 20)
assert(not vim.bo.modifiable and vim.bo.readonly and not vim.bo.autoread)
for _, key in ipairs({ "p", "q", "[m", "]m", "<leader>fp", "<leader>fl", "<leader>fa" }) do
  assert(vim.fn.maparg(key, "n", false, true).buffer ~= 1, "Reader overrides " .. key)
end
for _, key in ipairs({ "<leader>rmp", "<leader>rml", "<leader>rmb", "<leader>rmn" }) do
  assert(vim.fn.maparg(key, "n", false, true).buffer == 1, "Missing reader mapping " .. key)
end
assert(reader.picker_items()[1].text:find("search-only-token", 1, true))
assert(reader.picker_items()[1].label:find("user prompt", 1, true))
assert(reader.picker_items()[1].file == first.sourcePath)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
review.annotation.add({ body = "first draft" })
-- A pending annotation input must not deposit its captured target into the
-- next message store. Accept it into the originating context after switching.
local bridge_input = package.loaded["agent_bridge.input"]
local pending
package.loaded["agent_bridge.input"] = { new = function(opts)
  pending = opts.on_accept
  return { open = function() end }
end }
review.annotation.add()
package.loaded["agent_bridge.input"] = bridge_input
vim.fn.maparg("<leader>rmb", "n", false, true).callback()
assert(vim.api.nvim_buf_get_name(0) == second.sourcePath)
local accepted
pending("late first-message comment", nil, function(ok) accepted = ok end)
assert(accepted == true)
local second_buf = vim.api.nvim_get_current_buf()
assert(#review.annotation.list({ all = true }) == 0)
review.annotation.add({ body = "second draft" })
vim.fn.maparg("<leader>rmn", "n", false, true).callback()
assert(vim.api.nvim_buf_get_name(0) == first.sourcePath)
assert(vim.api.nvim_win_get_cursor(0)[1] == 3)
assert(#review.annotation.list({ all = true }) == 2)
assert(review.annotation.list()[1].body == "first draft")
-- Direct :buffer changes use exactly the same persistence boundary.
vim.api.nvim_set_current_buf(second_buf)
assert(review.annotation.list()[1].body == "second draft")
-- Staging and the reader poller must leave the editor's statusline alone.
-- Default mapped submit-and-close is exercised through real Agent Bridge in
-- feedback_stage.lua; this navigation case explicitly keeps its view open.
local transport = require("agent_bridge.transport")
local original_send, staged = transport.send
transport.send = function(message, opts, done)
  staged = { message = message, opts = opts }
  done(true)
end
local statusline = "editor-owned statusline"
vim.wo.statusline = statusline
assert(feedback.submit({ quit = false }))
transport.send = original_send
assert(staged.message:find("second draft", 1, true))
assert(staged.opts.submit == false and staged.opts.switch_to_target == true)
assert(vim.wo.statusline == statusline, "Feedback submission overwrote the editor's statusline")
assert(reader.refresh())
vim.wait(1100)
assert(vim.wo.statusline == statusline, "Reader polling overwrote the editor's statusline")
local second_payload = vim.fs.dirname(second.sourcePath) .. "/feedback.json"
assert(vim.fn.filereadable(second_payload) == 0, "Reader staging must not write an unused handoff file")
assert(staged.message:find("Assistant response ID: `" .. second.entryId .. "`", 1, true))
assert(not reader.status():find("/feedback collect", 1, true))
vim.api.nvim_set_current_buf(first_buf)
assert(review.annotation.list()[1].body == "first draft")
assert(vim.fn.filereadable(vim.fs.dirname(first.sourcePath) .. "/feedback.json") == 0)

-- Real installed Snacks picker: full file preview, full-text matching, and
-- cancellation must not change the selected reply, draft, or cursor.
local picker = assert(reader.picker())
assert(vim.wait(2000, function() return picker:current() ~= nil end))
assert(picker.opts.preview == "file")
assert(picker.opts.previewers.file.max_size == math.huge)
assert(type(picker.opts.actions.feedback_toggle_all) == "function")
assert(vim.fn.maparg("<C-a>", "i") ~= "")
picker.input:set("'search-only-token-reply-7")
picker:find()
assert(vim.wait(2000, function()
  return picker.list:count() == 1 and picker:current().entryId == "reply-7"
end))
assert(vim.wait(2000, function()
  local buf = picker.preview.win.buf
  return buf and vim.api.nvim_buf_is_valid(buf)
    and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false),
      { "# reply-7", "", "search-only-token-reply-7", "tail" })
end))
picker:close()
vim.wait(30)
assert(vim.api.nvim_get_current_buf() == first_buf)
assert(vim.api.nvim_win_get_cursor(0)[1] == 3)
assert(review.annotation.list()[1].body == "first draft")

local before = vim.api.nvim_buf_get_lines(first_buf, 0, -1, false)
local next_reply = message("newest", true, true)
table.insert(document.messages, 1, next_reply)
document.latestEntryId = next_reply.entryId
write(path, document)
assert(vim.wait(2200, function() return reader.status():find("newer available", 1, true) ~= nil end))
assert(vim.api.nvim_get_current_buf() == first_buf)
assert(vim.api.nvim_win_get_cursor(0)[1] == 3)
assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(first_buf, 0, -1, false)))
assert(reader.latest())
assert(vim.api.nvim_buf_get_name(0) == next_reply.sourcePath)
assert(reader.toggle_all())
assert(#reader.visible_messages() == 26)
assert(reader.select("progress"))
assert(reader.select("other-branch"))
assert(not reader.toggle_all())
assert(#reader.visible_messages() == 20)

-- A branch with no completed reply has no latest target. Keep the current view
-- and allow deliberate browsing instead of selecting progress or another branch.
local no_latest = vim.deepcopy(document)
no_latest.latestEntryId = ""
for _, entry in ipairs(no_latest.messages) do entry.onBranch = entry.entryId == "progress" end
write(path, no_latest)
local current_buf = vim.api.nvim_get_current_buf()
assert(reader.refresh())
assert(not reader.status():find("newer available", 1, true))
assert(not reader.latest())
assert(reader.status():find("No completed reply yet", 1, true))
assert(vim.api.nvim_get_current_buf() == current_buf)
assert(reader.toggle_all())
assert(reader.select("other-branch"))
assert(not reader.toggle_all())
write(path, document)
assert(reader.latest())

-- Catalogue replacement is validated before becoming active.
local invalid = vim.deepcopy(document)
invalid.messages[1].feedbackStatePath = second.feedbackStatePath
write(path, invalid)
assert(not reader.refresh())
invalid = vim.deepcopy(document)
invalid.messages[1].entryId = "different-identity"
write(path, invalid)
assert(not reader.refresh())
invalid = vim.deepcopy(document)
invalid.messages[1].sourcePath = ""
write(path, invalid)
assert(not reader.refresh())
invalid = vim.deepcopy(document)
invalid.piSessionId = "other-session"
write(path, invalid)
assert(not reader.refresh())
write(path, document)
assert(reader.refresh())
-- A symlink to another store is never accepted.
vim.fn.delete(next_reply.feedbackStatePath)
assert(vim.uv.fs_symlink(second.feedbackStatePath, next_reply.feedbackStatePath))
assert(not reader.refresh())
vim.fn.delete(next_reply.feedbackStatePath)
assert(reader.refresh())

-- Invalid drafts cannot overwrite another store on load failure or debounce.
local broken = document.messages[4]
vim.fn.writefile({ "not json" }, broken.feedbackStatePath)
assert(reader.select(first.entryId))
assert(not reader.select(broken.entryId))
assert(vim.api.nvim_buf_get_name(0) == first.sourcePath)
assert(review.annotation.list()[1].body == "first draft")
vim.api.nvim_set_current_buf(vim.fn.bufnr(broken.sourcePath))
assert(not review.annotation.add({ body = "must not accept unsaveable feedback" }))
assert(reader.select(first.entryId))
vim.wait(30)
assert(vim.fn.readfile(broken.feedbackStatePath)[1] == "not json")
vim.fn.delete(broken.feedbackStatePath)
assert(reader.select(broken.entryId))
assert(not require("agent_review.context").for_buffer().closed)

-- Discard clears only this message, retaining source/metadata and other drafts.
assert(reader.select(second.entryId))
assert(feedback.discard({ quit = false }))
assert(#review.annotation.list({ all = true }) == 0)
assert(vim.fn.filereadable(second.sourcePath) == 1)
assert(vim.fn.filereadable(second.metadataPath) == 1)
assert(vim.fn.filereadable(second_payload) == 0)
assert(reader.select(first.entryId))
assert(review.annotation.list()[1].body == "first draft")
-- No explicit Keep or Submit disposition: ordinary qa! must retain this draft.
-- Reopen verifies draft survival.
reader.close()
