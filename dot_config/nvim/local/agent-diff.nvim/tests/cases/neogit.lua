local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
require("neogit").setup({
  kind = "replace",
  treesitter_diff_highlight = true,
  word_diff_highlight = false,
  diff_viewer = "codediff",
  integrations = { codediff = true },
})
require("agent_diff.neogit").setup()
vim.cmd.edit(vim.fn.fnameescape(path))
vim.cmd("Neogit")
assert(vim.wait(10000, function()
  return vim.bo.filetype == "NeogitStatus"
end, 20))
local bufnr = vim.api.nvim_get_current_buf()
local function find(text)
  for line, value in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if value:find(text, 1, true) then
      return line
    end
  end
end
assert(vim.wait(10000, function()
  return find("sample.lua") ~= nil
end, 20))
vim.api.nvim_win_set_cursor(0, { find("sample.lua"), 0 })
vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "xt", false)
assert(vim.wait(10000, function()
  return find("-local old_name") ~= nil
end, 20))
local found_agent_inner = false
for name, namespace in pairs(vim.api.nvim_get_namespaces()) do
  if name:find("NeogitDiffHighlight", 1, true) then
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })) do
      local highlight = mark[4].hl_group
      found_agent_inner = found_agent_inner or highlight == "CodeDiffCharDelete" or highlight == "CodeDiffCharInsert"
    end
  end
end
assert(found_agent_inner)
assert(#vim.api.nvim_list_tabpages() == 1)
assert(vim.fn.maparg("dd", "n", false, true).lhs == nil)
assert(vim.fn.maparg("di", "n", false, true).lhs == nil)

-- `du` is the real Neogit DiffPopup followed by its unstaged action. With two
-- changed files it opens a changeset and shows the sidebar by default.
vim.api.nvim_feedkeys("du", "xt", false)
assert(vim.wait(10000, function()
  local session = require("agent_diff").get_session()
  return session and #session.files == 2 and session.explorer_win and vim.api.nvim_win_is_valid(session.explorer_win)
end, 20), "Neogit du did not open a multi-file changeset")
local multi = require("agent_diff").get_session()
assert(multi.parking_win and vim.api.nvim_win_is_valid(multi.parking_win))
assert(vim.api.nvim_win_get_config(multi.parking_win).hide)
assert(vim.wait(3000, function()
  return multi.index_watcher ~= nil and multi.modified_buf ~= nil
end, 20), "changeset watchers were not installed")
local redraw_ok, redraw_err = pcall(function()
  require("neogit.buffers.status").instance():redraw()
end)
assert(redraw_ok, redraw_err)
local staged_externally = vim.system({ "git", "add", "second.txt" }, { text = true }):wait()
assert(staged_externally.code == 0, staged_externally.stderr)
assert(vim.wait(10000, function()
  return #multi.files == 1 and multi.files[1].path == "sample.lua"
end, 20), "external staging did not refresh the unstaged changeset: " .. vim.inspect(multi.files))
local reset_externally = vim.system({ "git", "reset", "--", "second.txt" }, { text = true }):wait()
assert(reset_externally.code == 0, reset_externally.stderr)
assert(vim.wait(10000, function()
  return #multi.files == 2
end, 20), "external index reset did not refresh the changeset")
require("agent_diff").next_file()
assert(vim.wait(10000, function()
  local context = multi.modified_buf and vim.b[multi.modified_buf].agent_diff_context
  return context and context.path == "second.txt"
end, 20))
vim.fn.writefile({ "second external" }, vim.fs.dirname(path) .. "/second.txt")
assert(vim.wait(10000, function()
  return multi.modified_lines and multi.modified_lines[1] == "second external"
end, 20), "external working-tree edit did not refresh the changeset")
vim.fn.writefile({ "second new" }, vim.fs.dirname(path) .. "/second.txt")
assert(vim.wait(10000, function()
  return multi.modified_lines and multi.modified_lines[1] == "second new"
end, 20))
require("agent_diff").prev_file()
assert(vim.wait(10000, function()
  local context = multi.modified_buf and vim.b[multi.modified_buf].agent_diff_context
  return context and context.path == "sample.lua"
end, 20))
require("agent_diff").toggle_sidebar()
assert(not multi.explorer_win)
require("agent_diff").toggle_sidebar()
assert(multi.explorer_win and vim.api.nvim_win_is_valid(multi.explorer_win))
require("agent_diff").close()
assert(vim.wait(3000, function()
  return vim.bo.filetype == "NeogitStatus"
end, 20))

vim.api.nvim_win_set_cursor(0, { assert(find("sample.lua")), 0 })
vim.api.nvim_feedkeys("dd", "xt", false)
assert(vim.wait(10000, function()
  local session = require("agent_diff").get_session()
  return session and session.layout == "inline" and #session.files == 1 and not session.explorer_win
end, 20), "Neogit dd did not open a single-file Agent Diff")
assert(#vim.api.nvim_list_tabpages() == 1)
require("agent_diff").close()
assert(vim.wait(3000, function()
  return vim.bo.filetype == "NeogitStatus"
end, 20))

vim.api.nvim_win_set_cursor(0, { assert(find("+local new_name")), 0 })
vim.api.nvim_feedkeys("s", "xt", false)
assert(vim.wait(10000, function()
  local result = vim.system({ "git", "diff", "--cached", "--name-only" }, { text = true }):wait()
  return result.stdout:find("sample.lua", 1, true) ~= nil
end, 20), "staging the highlighted hunk failed")
assert(vim.wait(10000, function()
  return vim.bo.filetype == "NeogitStatus"
end, 20))
vim.api.nvim_feedkeys("ds", "xt", false)
assert(vim.wait(10000, function()
  local session = require("agent_diff").get_session()
  return session
    and session.original_revision == "HEAD"
    and session.modified_revision == "INDEX"
    and #session.files == 1
    and not session.explorer_win
    and session.modified_scratch
end, 20), "Neogit ds did not open the staged changeset")
require("agent_diff").close()
print("PASS neogit.lua")
