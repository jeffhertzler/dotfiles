local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
local root = vim.fs.dirname(path)
local function git(...)
  local result = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end

git("reset", "--hard", "-q", "HEAD")
local old, new = {}, {}
for index = 1, 2500 do
  old[index] = string.format("old value %04d repeated token", index)
  new[index] = string.format("new value %04d different token", 2501 - index)
end
vim.fn.writefile(old, path)
git("add", "sample.lua")
git("commit", "-qm", "large baseline")
vim.fn.writefile(new, path)
vim.cmd.edit(vim.fn.fnameescape(path))

local diff = require("agent_diff")
diff.setup({ initial_timeout_ms = 100, live_timeout_ms = 50, debounce_ms = 40 })
local started = vim.uv.hrtime()
diff.open()
assert(vim.wait(5000, function()
  local session = diff.get_session()
  return session and session.diff_result and #session.diff_result.changes > 0
end, 10), "large diff did not render within its budget")
local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
assert(elapsed_ms < 5000, string.format("large diff took %.1fms", elapsed_ms))
local session = assert(diff.get_session())
assert(#vim.api.nvim_list_tabpages() == 1)
assert(vim.wo[session.modified_win].winbar:find("Agent Diff", 1, true))

vim.api.nvim_buf_set_lines(session.modified_buf, -1, -1, false, { "external tail" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = session.modified_buf })
assert(vim.wait(10000, function()
  return session.modified_lines[#session.modified_lines] == "external tail"
end, 10), "large live diff did not refresh: " .. tostring(session.modified_lines[#session.modified_lines]))
diff.close()
assert(diff.get_session() == nil)
print(string.format("PASS large_diff.lua (%.1fms, timeout=%s)", elapsed_ms, tostring(session.diff_result.hit_timeout)))
