local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
require("gitsigns").setup({
  on_attach = require("agent_diff.gitsigns").setup_buffer,
})
vim.cmd.edit(vim.fn.fnameescape(path))
assert(vim.wait(10000, function()
  local hunks = require("gitsigns").get_hunks(0)
  return hunks and #hunks > 0
end, 20))
vim.api.nvim_win_set_cursor(0, { 1, 0 })
require("agent_diff.gitsigns").preview_hunk()
local namespace = assert(vim.api.nvim_get_namespaces()["agent-diff-gitsigns-preview"])
local char, virtual = false, false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
  local details = mark[4]
  char = char or details.hl_group == "CodeDiffCharInsert"
  virtual = virtual or details.virt_lines ~= nil
end
assert(char and virtual)
require("agent_diff").open_side("INDEX")
assert(vim.wait(10000, function()
  local session = require("agent_diff").get_session()
  return session and session.original_win
end, 20))
assert(#vim.api.nvim_list_tabpages() == 1)
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
require("agent_diff").close()
print("PASS gitsigns.lua")
