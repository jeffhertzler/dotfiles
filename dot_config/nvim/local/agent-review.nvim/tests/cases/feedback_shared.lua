local review = require("agent_review")
local reader = require("agent_review.feedback_reader")
local persistence = require("agent_review.persistence")
local render = require("agent_review.render")
local root = assert(vim.env.AGENT_REVIEW_TEST_TMP)
vim.fn.mkdir(root, "p")
local function write(path, value)
  vim.fn.writefile({ vim.json.encode(value) }, path)
end
local function read(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end
local function catalogue(name)
  local directory = root .. "/" .. name
  vim.fn.mkdir(directory, "p")
  local doc = { schemaVersion = 1, piSessionId = name, latestEntryId = "one", messages = {} }
  for _, id in ipairs({ "one", "two" }) do
    local dir = directory .. "/" .. id
    vim.fn.mkdir(dir, "p")
    local entry = { entryId = id, title = id, prompt = name, timestamp = "2026-07-01",
      onBranch = true, finished = true, sourcePath = dir .. "/source.md",
      metadataPath = dir .. "/metadata.json", feedbackStatePath = dir .. "/annotations.json" }
    vim.fn.writefile({ "# " .. name, id, "last line" }, entry.sourcePath)
    write(entry.metadataPath, { schemaVersion = 1, reader = true, piSessionId = name,
      assistantMessageId = id, feedbackDirectory = dir, sourcePath = entry.sourcePath,
      feedbackPath = dir .. "/feedback.json" })
    table.insert(doc.messages, entry)
  end
  local path = directory .. "/catalogue.json"
  write(path, doc)
  return path, doc
end
local a, adoc = catalogue("conversation-a")
local b, bdoc = catalogue("conversation-b")
local function remote(action, path, state)
  local result = reader.remote({ action = action, cataloguePath = path, feedbackStatePath = state })
  assert(result.ok, result.error)
  assert(pcall(vim.json.encode, result))
  return result.open
end

vim.cmd("edit " .. vim.fn.fnameescape(vim.env.AGENT_REVIEW_TEST_FILE))
local code = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local code_annotation = assert(review.annotation.add({ body = "code review" }))
local code_session = review.session.current()
vim.cmd("vsplit")
local code_tab = vim.api.nvim_get_current_tabpage()
local code_windows = vim.api.nvim_tabpage_list_wins(code_tab)
local code_win = vim.api.nvim_get_current_win()
vim.wo.winbar = "existing winbar"
vim.wo.statusline = "existing statusline"
local original_env = vim.env.NVIM_AGENT_REVIEW_STATE
local function untouched()
  assert(vim.api.nvim_tabpage_is_valid(code_tab))
  assert(vim.deep_equal(code_windows, vim.api.nvim_tabpage_list_wins(code_tab)))
  for _, win in ipairs(code_windows) do
    assert(vim.api.nvim_win_get_buf(win) == code)
    assert(vim.api.nvim_win_get_cursor(win)[1] == 2)
  end
  assert(vim.wo[code_win].winbar == "existing winbar")
  assert(vim.wo[code_win].statusline == "existing statusline")
  assert(vim.env.NVIM_AGENT_REVIEW_STATE == original_env)
end
assert(review.feedback_context_version == 1)
local old = package.loaded.agent_review
package.loaded.agent_review = {}
assert(not reader.remote({ action = "open", cataloguePath = a }).ok)
package.loaded.agent_review = old
assert(#vim.api.nvim_list_tabpages() == 1)
assert(not remote("status", a))
assert(not remote("focus", a))
assert(vim.api.nvim_get_current_tabpage() == code_tab)
assert(remote("open", a))
local a_tab = vim.api.nvim_get_current_tabpage()
local a_buf = vim.api.nvim_get_current_buf()
assert(a_tab ~= code_tab and #vim.api.nvim_list_tabpages() == 2)
assert(review.annotation.add({ body = "A draft" }).id == code_annotation.id)
local a_session = review.session.current()
local pending = assert(review.annotation.add())
vim.api.nvim_buf_set_lines(pending.buffer, 0, -1, false, { "A delayed addition" })
assert(remote("open", b))
local b_tab = vim.api.nvim_get_current_tabpage()
local b_buf = vim.api.nvim_get_current_buf()
assert(b_tab ~= a_tab and #vim.api.nvim_list_tabpages() == 3)
assert(review.annotation.add({ body = "B draft" }).id == code_annotation.id)
pending:_accept({ action = "save" })
assert(vim.api.nvim_buf_is_valid(a_buf))
vim.api.nvim_set_current_tabpage(b_tab)
assert(#review.annotation.list({ all = true }) == 1)
assert(review.annotation.get(code_annotation.id).body == "B draft")
assert(remote("focus", a))
assert(vim.api.nvim_get_current_tabpage() == a_tab)
assert(#review.annotation.list({ all = true }) == 2)
assert(review.session.current().id == a_session.id)
local edit = assert(review.annotation.edit(code_annotation.id))
vim.api.nvim_buf_set_lines(edit.buffer, 0, -1, false, { "A edited later" })
vim.api.nvim_set_current_tabpage(code_tab)
edit:_accept({ action = "save" })
vim.api.nvim_set_current_tabpage(code_tab)
assert(review.annotation.get(code_annotation.id).body == "code review")
assert(review.session.current().id == code_session.id)
assert(#review.annotation.list({ all = true }) == 1)

-- Background rendering and debounced persistence select their own buffers.
render.refresh_buffer(a_buf)
render.refresh_buffer(b_buf)
render.refresh_visible()
local ns = vim.api.nvim_get_namespaces().agent_review_render
local function rendered(buf)
  return vim.inspect(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }))
end
assert(rendered(a_buf):find("A edited later", 1, true))
assert(not rendered(a_buf):find("B draft", 1, true))
assert(rendered(b_buf):find("B draft", 1, true))
assert(rendered(code):find("code review", 1, true))
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = a_buf })
assert(vim.wait(1000, function()
  return vim.fn.filereadable(adoc.messages[1].feedbackStatePath) == 1
    and vim.fn.filereadable(bdoc.messages[1].feedbackStatePath) == 1
end))
assert(read(adoc.messages[1].feedbackStatePath).annotations[1].body == "A edited later")
assert(read(bdoc.messages[1].feedbackStatePath).annotations[1].body == "B draft")
assert(read(original_env).annotations[1].body == "code review")
untouched()

-- Commands and reload affect only the targeted message, even with matching IDs.
assert(remote("focus", b))
vim.cmd("AgentReview resolve " .. code_annotation.id)
assert(review.annotation.get(code_annotation.id).status == "resolved")
assert(remote("focus", a))
assert(review.annotation.get(code_annotation.id).status == "open")
assert(persistence.reload())
assert(#review.annotation.list({ all = true }) == 2)
assert(review.annotation.get(code_annotation.id).body == "A edited later")
assert(remote("open", a, adoc.messages[2].feedbackStatePath))
assert(#vim.api.nvim_list_tabpages() == 3)
assert(#review.annotation.list({ all = true }) == 0)
assert(review.annotation.add({ body = "A second message" }).id == code_annotation.id)
assert(remote("open", a, adoc.messages[1].feedbackStatePath))
assert(vim.api.nvim_get_current_buf() == a_buf)

-- Status is a read-only query. It does not focus, refresh, or create anything.
vim.api.nvim_set_current_tabpage(code_tab)
local before = vim.fn.readfile(adoc.messages[1].feedbackStatePath)
assert(remote("status", a))
assert(vim.api.nvim_get_current_tabpage() == code_tab)
assert(vim.deep_equal(before, vim.fn.readfile(adoc.messages[1].feedbackStatePath)))
local failure = reader.remote({ action = "open", cataloguePath = root .. "/missing.json" })
assert(not failure.ok)
assert(vim.api.nvim_get_current_tabpage() == code_tab)
assert(#vim.api.nvim_list_tabpages() == 3)

-- Ordinary :q flushes just A, disposes its poller, and cancels its pending input.
assert(remote("focus", a))
local abandoned = assert(review.annotation.add())
vim.api.nvim_buf_set_lines(abandoned.buffer, 0, -1, false, { "must not resurrect" })
assert(remote("focus", a))
vim.cmd("quit")
assert(not remote("status", a))
assert(remote("status", b))
assert(vim.api.nvim_buf_is_valid(a_buf), "hidden snapshot should be reusable")
local kept = read(adoc.messages[1].feedbackStatePath)
assert(#kept.annotations == 2)
-- Reopen reuses the hidden snapshot, reloads the draft, and leaves B untouched.
assert(remote("open", a))
assert(vim.api.nvim_get_current_buf() == a_buf)
assert(#review.annotation.list({ all = true }) == 2)
abandoned:_accept({ action = "save" })
assert(#review.annotation.list({ all = true }) == 2)
abandoned:close()
assert(require("agent_review.feedback").keep())
assert(not remote("status", a))
assert(remote("status", b))
assert(#vim.api.nvim_list_tabpages() == 2)
untouched()

-- Once open=false, /feedback clear can remove files without a timer, stale
-- input callback, background render, hidden buffer command, or VimLeave save
-- recreating them.
vim.fn.delete(vim.fs.dirname(a), "rf")
render.refresh_buffer(a_buf)
vim.api.nvim_set_current_buf(a_buf)
assert(not require("agent_review.feedback").submit({ quit = false }))
assert(not review.annotation.add({ body = "closed" }))
vim.api.nvim_set_current_buf(b_buf)
assert(require("agent_review.feedback").keep())
vim.api.nvim_set_current_tabpage(code_tab)
vim.wait(1200)
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(vim.fn.isdirectory(vim.fs.dirname(a)) == 0)
assert(not remote("status", a))
assert(not remote("status", b))
assert(review.annotation.get(code_annotation.id).body == "code review")
untouched()

-- Failed final writes protect the catalogue even after its window has closed.
local c, cdoc = catalogue("save-failure")
assert(remote("open", c))
review.annotation.add({ body = "keep despite write failure" })
assert(persistence.save_now())
local state_path = cdoc.messages[1].feedbackStatePath
vim.fn.delete(state_path)
vim.fn.mkdir(state_path)
vim.cmd("quit")
assert(remote("status", c), "unsaved drafts must block catalogue clearing")
vim.fn.delete(state_path, "d")
-- The Pi launcher calls focus for retained handles, not open. Recovery must
-- restore the protected reader rather than silently focusing an unrelated tab.
assert(remote("focus", c))
assert(review.annotation.list()[1].body == "keep despite write failure")
assert(require("agent_review.feedback").keep())
assert(not remote("status", c))
assert(read(state_path).annotations[1].body == "keep despite write failure")
untouched()

-- Closing one split retains the remaining feedback view and its draft store.
local split_path, split_doc = catalogue("split-reader")
assert(remote("open", split_path))
local original_window = vim.api.nvim_get_current_win()
local split_context = require("agent_review.context").for_buffer()
review.annotation.add({ body = "split draft" })
vim.cmd("vsplit")
local remaining_window = vim.api.nvim_get_current_win()
vim.api.nvim_win_close(original_window, false)
assert(remote("status", split_path))
assert(not split_context.closed)
assert(remote("focus", split_path))
assert(vim.api.nvim_get_current_win() == remaining_window)
review.annotation.add({ body = "still open" })
vim.cmd("quit")
assert(not remote("status", split_path))
assert(#read(split_doc.messages[1].feedbackStatePath).annotations == 2)
untouched()

-- A wiped source buffer cannot hide its outstanding store from disposal.
local d, ddoc = catalogue("wiped-buffer")
assert(remote("open", d))
local wiped = vim.api.nvim_get_current_buf()
review.annotation.add({ body = "wiped draft" })
local delayed = review.annotation.add()
vim.api.nvim_buf_set_lines(delayed.buffer, 0, -1, false, { "late wiped" })
assert(remote("focus", d))
vim.api.nvim_buf_delete(wiped, { force = true })
if remote("status", d) then
  assert(remote("focus", d))
  vim.cmd("quit")
end
assert(not remote("status", d))
assert(read(ddoc.messages[1].feedbackStatePath).annotations[1].body == "wiped draft")
vim.fn.delete(vim.fs.dirname(d), "rf")
delayed:_accept({ action = "save" })
delayed:close()
vim.wait(150)
assert(vim.fn.isdirectory(vim.fs.dirname(d)) == 0)
untouched()
