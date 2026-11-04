local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
local root = vim.fs.dirname(path)
local diff = require("agent_diff")
local function git(...)
  local result = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end

-- Both files differ only in indentation and trailing whitespace.
local working = { "  local old_name = 1\t", "\tkeep  " }
vim.fn.writefile(working, path)
vim.fn.writefile({ "  second old\t" }, root .. "/second.txt")
local index_before = git("write-tree")
vim.cmd.edit(vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local function wait_for_view(predicate)
  assert(vim.wait(10000, function()
    local session = diff.get_session()
    return session and session.modified_buf and session.original_lines and #session.original_lines > 0 and predicate(session)
  end, 10), "whitespace view did not settle")
  return diff.get_session()
end
local function changes(count)
  return function(session)
    return #session.diff_result.changes == count
  end
end
local function has_changes(session)
  return #session.diff_result.changes > 0
end

local session = diff.open()
wait_for_view(changes(0))
assert(session.ignore_trim_whitespace == true)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), working))
assert(not vim.bo[buf].modified)

vim.cmd("AgentDiffWhitespace")
assert(session.ignore_trim_whitespace == false)
assert(has_changes(session))
diff.toggle()
assert(session.layout == "side-by-side")
assert(has_changes(session))
vim.cmd("AgentDiffWhitespace")
assert(session.ignore_trim_whitespace == true)
assert(#session.diff_result.changes == 0)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), working))
assert(not vim.bo[buf].modified)
diff.close()

-- New views default back to ignoring whitespace; explicit false still works.
diff.open()
wait_for_view(changes(0))
diff.close()
diff.open({ ignore_trim_whitespace = false })
wait_for_view(has_changes)

-- Opening the sidebar preserves the current choice, even when it is false.
diff.toggle_sidebar()
session = wait_for_view(function(current)
  return current.kind == "changeset" and current.ignore_trim_whitespace == false and has_changes(current)
end)
assert(#session.files == 2)
vim.cmd("AgentDiffWhitespace")
assert(#session.diff_result.changes == 0)
diff.next_file()
wait_for_view(function(current)
  return current.files[current.index].path == "second.txt"
    and current.ignore_trim_whitespace == true and #current.diff_result.changes == 0
    and current.modified_buf ~= buf
end)
diff.toggle()
assert(session.layout == "side-by-side")
assert(#session.diff_result.changes == 0)
vim.cmd("AgentDiffWhitespace")
assert(has_changes(session))
diff.close()

-- Direct changesets also inherit the default and respect an explicit opt-out.
local opts = {
  root = root,
  files = { { path = "sample.lua", status = "M" }, { path = "second.txt", status = "M" } },
  original_revision = "HEAD",
  modified_revision = "WORKING",
}
session = diff.open_changeset(opts)
wait_for_view(changes(0))
assert(session.ignore_trim_whitespace == true)
diff.close()
session = diff.open_changeset(vim.tbl_extend("force", opts, { ignore_trim_whitespace = false }))
wait_for_view(has_changes)
assert(session.ignore_trim_whitespace == false)
diff.close()

-- Real edits and internal whitespace are still visible, including unsaved edits.
vim.api.nvim_set_current_buf(buf)
session = diff.open()
wait_for_view(changes(0))
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  local old_name = 2\t", "\tkeep  " })
diff.refresh()
assert(has_changes(session))
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  local  old_name = 1\t", "\tkeep  " })
diff.refresh()
assert(has_changes(session))
local unsaved = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
vim.cmd("AgentDiffWhitespace")
vim.cmd("AgentDiffWhitespace")
assert(vim.bo[buf].modified)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), unsaved))
assert(vim.deep_equal(vim.fn.readfile(path), working))
assert(git("write-tree") == index_before, "whitespace mode changed the Git index")
diff.close()
print("PASS whitespace.lua")
