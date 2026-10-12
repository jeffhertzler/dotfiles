local root = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(root, "p")
local review = require("agent_review")
local reader = require("agent_review.feedback_reader")
local feedback = require("agent_review.feedback")
local function json(path, value) vim.fn.writefile({ vim.json.encode(value) }, path) end
local function catalogue(name)
  local dir = root .. "/" .. name .. "/reply"
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile({ "# Reply", "Details" }, dir .. "/source.md")
  json(dir .. "/metadata.json", { schemaVersion = 1, reader = true, piSessionId = name,
    assistantMessageId = name .. "-reply", feedbackDirectory = dir,
    sourcePath = dir .. "/source.md", feedbackPath = dir .. "/feedback.json" })
  local path = root .. "/" .. name .. "/catalogue.json"
  json(path, { schemaVersion = 1, piSessionId = name, latestEntryId = name .. "-reply", messages = {
    { entryId = name .. "-reply", title = "Reply", prompt = "Question", timestamp = "now",
      onBranch = true, finished = true, sourcePath = dir .. "/source.md",
      metadataPath = dir .. "/metadata.json", feedbackStatePath = dir .. "/annotations.json" },
  } })
  return path, dir
end
local function open(path)
  local result = reader.remote({ action = "open", cataloguePath = path })
  assert(result.ok, result.error)
  return vim.api.nvim_get_current_tabpage()
end

vim.cmd("edit " .. vim.fn.fnameescape(assert(vim.env.AGENT_REVIEW_TEST_FILE)))
local code_tab = vim.api.nvim_get_current_tabpage()
local code_buf = vim.api.nvim_get_current_buf()
review.annotation.add({ body = "ordinary code note" })
local a, a_dir = catalogue("a")
local b = catalogue("b")
local a_tab = open(a)
review.annotation.add({ body = "feedback A" })
local submit = vim.fn.maparg("<leader>rs", "n", false, true).callback

-- Exercise real Agent Bridge target selection and transport. Only the external
-- Herdr boundary is faked; never send test text into a person's agent.
vim.env.HERDR_ENV, vim.env.HERDR_WORKSPACE_ID, vim.env.HERDR_TAB_ID, vim.env.HERDR_PANE_ID = "1", "w-test", "t-editor", "p-editor"
local calls, failed, multiple = {}, false, false
local editor, cursor = "already typing AFTER", #"already typing "
local util = require("agent_bridge.util")
local original_herdr = util.herdr
util.herdr = function(...)
  local args = { ... }; calls[#calls + 1] = args
  if args[1] == "agent" and args[2] == "list" then
    local agents = { { workspace_id = "w-test", tab_id = "t-editor", pane_id = "p-pi", agent = "pi" } }
    if multiple then agents[2] = { workspace_id = "w-test", tab_id = "t-editor", pane_id = "p-other", agent = "pi" } end
    return vim.json.encode({ result = { agents = agents } })
  end
  if args[1] == "pane" and args[2] == "send-text" then
    if failed then return nil, "test transport failure" end
    assert(args[3] == "p-pi")
    assert(args[4]:sub(1, 6) == "\27[200~" and args[4]:sub(-6) == "\27[201~")
    local text = args[4]:sub(7, -7)
    editor = editor:sub(1, cursor) .. text .. editor:sub(cursor + 1)
    return ""
  end
  assert(args[1] == "agent" and args[2] == "focus" and args[3] == "p-pi", "must stage and focus, never prompt/Enter")
  -- Closing the feedback view is allowed only after paste and focus complete.
  assert(vim.api.nvim_tabpage_is_valid(a_tab))
  return ""
end

-- Reader staging must not depend on the obsolete collection payload. Simulate
-- a write failure there, and preserve any existing saved payload untouched.
local payload_path = a_dir .. "/feedback.json"
vim.fn.writefile({ "existing saved submission" }, payload_path)
local original_writefile = vim.fn.writefile
vim.fn.writefile = function(lines, path, ...)
  assert(path:sub(1, #payload_path) ~= payload_path, "Reader must not write feedback.json")
  return original_writefile(lines, path, ...)
end
submit()
vim.fn.writefile = original_writefile
assert(vim.fn.readfile(payload_path)[1] == "existing saved submission")
assert(#calls >= 3, "Submit must use Agent Bridge staging without /feedback collect")
assert(not vim.api.nvim_tabpage_is_valid(a_tab), "successful Submit must close its feedback view")
assert(vim.api.nvim_tabpage_is_valid(code_tab) and vim.api.nvim_get_current_buf() == code_buf)
assert(review.annotation.list()[1].body == "ordinary code note")
assert(editor:find("already typing ", 1, true) == 1 and editor:sub(-5) == "AFTER")
assert(editor:find("Assistant response ID: `a-reply`", 1, true))
assert(editor:find("> # Reply", 1, true) and editor:find("feedback A", 1, true))
assert(vim.fn.filereadable(a_dir .. "/annotations.json") == 1, "saved comments survive staging")

-- A failed paste retains the view and drafts for an ordinary Submit retry.
a_tab = open(a)
failed = true
local before = editor
vim.fn.maparg("<leader>rs", "n", false, true).callback()
assert(editor == before and vim.api.nvim_tabpage_is_valid(a_tab))
assert(review.annotation.list()[1].body == "feedback A")
failed = false

-- Target selection can complete after focus changes. Close the originating
-- reader, not whichever feedback or code buffer happens to be current.
multiple = true
local choose
local original_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  choose = function()
    for _, item in ipairs(items) do if item.pane_id == "p-pi" then callback(item); return end end
    error("test target missing")
  end
end
vim.fn.maparg("<leader>rs", "n", false, true).callback()
assert(choose and vim.api.nvim_tabpage_is_valid(a_tab))
local b_tab = open(b)
review.annotation.add({ body = "feedback B" })
choose()
assert(not vim.api.nvim_tabpage_is_valid(a_tab))
assert(vim.api.nvim_tabpage_is_valid(b_tab) and vim.api.nvim_get_current_tabpage() == b_tab)
assert(review.annotation.list()[1].body == "feedback B")
assert(not editor:find("feedback B", 1, true))

-- Cancelling target selection must not close the reader or change Pi input.
local cancel
vim.ui.select = function(_, _, callback) cancel = function() callback(nil) end end
before = editor
vim.fn.maparg("<leader>rs", "n", false, true).callback()
cancel()
assert(editor == before and vim.api.nvim_tabpage_is_valid(b_tab))
assert(review.annotation.list()[1].body == "feedback B")
vim.ui.select = original_select
util.herdr = original_herdr
