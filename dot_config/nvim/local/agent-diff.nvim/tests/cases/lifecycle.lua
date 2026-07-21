local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
vim.cmd.edit(vim.fn.fnameescape(path))
local diff = require("agent_diff")
diff.open()
assert(vim.wait(10000, function()
  local session = diff.get_session()
  return session and #session.diff_result.changes > 0
end, 10))
local session = assert(diff.get_session())
assert(session.layout == "inline")
assert(#vim.api.nvim_list_tabpages() == 1)
assert(vim.bo[session.modified_buf].modifiable)
diff.toggle()
assert(session.layout == "side-by-side")
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
assert(#vim.api.nvim_list_tabpages() == 1)
diff.toggle()
assert(session.layout == "inline")
assert(#vim.api.nvim_tabpage_list_wins(0) == 1)
assert(vim.api.nvim_buf_is_valid(session.original_buf))
diff.toggle()
assert(session.layout == "side-by-side")
diff.toggle()
assert(session.layout == "inline")
assert(vim.api.nvim_buf_is_valid(session.original_buf))
vim.api.nvim_buf_set_lines(session.modified_buf, -1, -1, false, { "live" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = session.modified_buf })
assert(vim.wait(3000, function()
  return session.modified_lines[#session.modified_lines] == "live"
end, 10))
diff.close()
assert(diff.get_session() == nil)

diff.inline("HEAD")
assert(vim.wait(10000, function()
  return diff.get_session() and #diff.get_session().diff_result.changes > 0
end, 10))
assert(diff.get_session().layout == "inline")
diff.inline("HEAD")
assert(diff.get_session() == nil)

diff.side_by_side("HEAD")
assert(vim.wait(10000, function()
  return diff.get_session() and diff.get_session().original_win
end, 10))
assert(diff.get_session().layout == "side-by-side")
diff.side_by_side("HEAD")
assert(diff.get_session() == nil)

diff.inline("HEAD")
assert(vim.wait(10000, function()
  return diff.get_session() and #diff.get_session().diff_result.changes > 0
end, 10))
diff.toggle_sidebar()
assert(vim.wait(10000, function()
  local current = diff.get_session()
  return current
    and current.kind == "changeset"
    and #current.files == 2
    and current.explorer_win
    and current.modified_buf
    and current.diff_result
    and #current.diff_result.changes > 0
end, 20), "direct diff sidebar did not resolve the changeset")
local files_session = diff.get_session()
diff.side_by_side()
assert(files_session.layout == "side-by-side")
assert(#vim.api.nvim_tabpage_list_wins(0) == 3)
diff.toggle_sidebar()
assert(not files_session.explorer_win)
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
diff.toggle_sidebar()
assert(files_session.explorer_win)
assert(#vim.api.nvim_tabpage_list_wins(0) == 3)
diff.inline()
assert(files_session.layout == "inline")
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
local first = files_session.index
diff.next_file()
assert(vim.wait(10000, function()
  return files_session.index ~= first and files_session.diff_result and #files_session.diff_result.changes > 0
end, 20))
diff.close()
assert(#vim.api.nvim_list_tabpages() == 1)
print("PASS lifecycle.lua")
