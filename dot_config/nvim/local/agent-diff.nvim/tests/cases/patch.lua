local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
local root = vim.fs.dirname(path)
local function git(...)
  local result = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout or ""
end
local function wait_for(predicate, message)
  assert(vim.wait(5000, predicate, 10), message)
end

git("reset", "--hard", "-q", "HEAD")
vim.fn.writefile({ "local staged_name = 2", "keep" }, path)
git("add", "sample.lua")
vim.fn.writefile({ "local staged_name = 2", "working keep", "unstaged one", "unstaged two" }, path)
vim.cmd.edit(vim.fn.fnameescape(path))

local patch = require("agent_diff.patch")
local workspace = assert(patch.open())
local function wait_apply(message)
  wait_for(function() return not workspace.applying end, message)
end
local function wait_refresh(message)
  local refresh_id = workspace.refresh_id
  wait_for(function() return workspace.completed_refresh_id == refresh_id end, message)
end
local function pane(section)
  return assert(workspace.panes[section], "missing " .. section .. " pane")
end
local function hunk_row(section)
  for row, metadata in pairs(pane(section).rows) do
    if metadata.kind == "hunk" then
      return row
    end
  end
end

wait_for(function()
  return workspace.sections[1]
    and workspace.sections[1].section == "unstaged"
    and #workspace.sections[1].hunks == 1
    and #workspace.sections[2].hunks == 1
    and workspace.panes.unstaged
    and workspace.panes.staged
end, "initial patch did not load")
assert(pane("unstaged").win ~= pane("staged").win and pane("unstaged").buf ~= pane("staged").buf)
for section, title in pairs({ unstaged = "Unstaged", staged = "Staged" }) do
  local current = pane(section)
  assert(vim.bo[current.buf].filetype == "agentpatch" and not vim.bo[current.buf].modifiable)
  local config = vim.api.nvim_win_get_config(current.win)
  assert(config.relative == "editor" and vim.inspect(config.border):find("╭", 1, true))
  assert(vim.inspect(config.title):find(title, 1, true))
  assert(vim.wo[current.win].winhighlight:find("FloatBorder:SnacksInputBorder", 1, true))
end

wait_for(function()
  local refined, syntax = false, false
  for _, section in ipairs({ "unstaged", "staged" }) do
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
      pane(section).buf,
      vim.api.nvim_get_namespaces().agent_diff_patch,
      0,
      -1,
      { details = true }
    )) do
      local group = mark[4].hl_group or ""
      refined = refined or group == "CodeDiffCharDelete" or group == "CodeDiffCharInsert"
      syntax = syntax or group:sub(1, 1) == "@"
    end
  end
  return refined and syntax
end, "patch highlighting did not finish")

local unstaged = pane("unstaged")
vim.api.nvim_set_current_win(unstaged.win)
patch.switch_pane(1)
assert(vim.api.nvim_get_current_win() == pane("staged").win)
patch.switch_pane(-1)
assert(vim.api.nvim_get_current_win() == unstaged.win)
assert(workspace.mode == "hunk")
assert(vim.inspect(vim.api.nvim_win_get_config(unstaged.win).footer):find("Hunk mode", 1, true))
patch.toggle_mode()
assert(workspace.mode == "line")
assert(vim.inspect(vim.api.nvim_win_get_config(unstaged.win).footer):find("Line mode", 1, true))
local selected_row
for row, metadata in pairs(unstaged.rows) do
  if metadata.kind == "add" and metadata.text == "working keep" then
    selected_row = row
  end
end
assert(selected_row)
vim.api.nvim_win_set_cursor(unstaged.win, { selected_row, 0 })
assert(patch.action("toggle"))
wait_apply("single-line stage did not apply")
local index_contents = git("show", ":sample.lua")
assert(index_contents:find("keep\nworking keep", 1, true), "staging +line also staged its paired -line")
assert(not index_contents:find("unstaged one", 1, true))
assert(git("diff", "--", "sample.lua") ~= "")
wait_refresh("partial stage did not refresh")
assert(workspace.panes.unstaged and workspace.panes.staged)
assert(vim.api.nvim_get_current_win() == workspace.panes.unstaged.win)

unstaged = pane("unstaged")
vim.api.nvim_set_current_win(unstaged.win)
vim.api.nvim_win_set_cursor(unstaged.win, { assert(hunk_row("unstaged")), 0 })
patch.toggle_mode()
assert(workspace.mode == "hunk")
assert(patch.action("toggle"))
wait_apply("hunk stage did not apply")
assert(git("diff", "--", "sample.lua") == "")
wait_for(function()
  return #workspace.sections[1].hunks == 0 and #workspace.sections[2].hunks == 1 and workspace.panes.staged
end, "stage did not refresh")
assert(not workspace.panes.unstaged)
assert(vim.api.nvim_get_current_win() == pane("staged").win)

local staged = pane("staged")
vim.api.nvim_win_set_cursor(staged.win, { assert(hunk_row("staged")), 0 })
assert(patch.action("delete"))
wait_apply("hunk unstage did not apply")
assert(git("diff", "--cached", "--", "sample.lua") == "")
wait_for(function()
  return #workspace.sections[1].hunks == 1 and #workspace.sections[2].hunks == 0 and workspace.panes.unstaged
end, "unstage did not refresh")
assert(not workspace.panes.staged)
assert(vim.api.nvim_get_current_win() == pane("unstaged").win)

unstaged = pane("unstaged")
vim.api.nvim_win_set_cursor(unstaged.win, { assert(hunk_row("unstaged")), 0 })
assert(patch.action("delete", { confirm = false }))
wait_apply("discard did not apply")
assert(git("diff", "--", "sample.lua") == "")
wait_for(function()
  return #workspace.sections[1].hunks == 0 and #workspace.sections[2].hunks == 0 and workspace.panes.empty
end, "discard did not refresh")
assert(pane("empty").lines[1]:find("No staged or unstaged changes", 1, true))
assert(vim.api.nvim_buf_get_lines(workspace.source_buf, 0, -1, false)[1] == "local old_name = 1")

vim.fn.writefile({ "delete one", "delete two", "keep" }, path)
git("add", "sample.lua")
git("commit", "-qm", "partial deletion baseline")
vim.fn.writefile({ "keep" }, path)
vim.api.nvim_buf_call(workspace.source_buf, function() vim.cmd("silent! checktime") end)
assert(patch.refresh())
wait_refresh("deletion did not load")
unstaged = pane("unstaged")
vim.api.nvim_set_current_win(unstaged.win)
local deleted_row
for row, metadata in pairs(unstaged.rows) do
  if metadata.kind == "delete" and metadata.text == "delete two" then
    deleted_row = row
  end
end
assert(deleted_row and patch.action("delete", { from_row = deleted_row, to_row = deleted_row, confirm = false }))
wait_apply("partial discard did not apply")
local working_contents = table.concat(vim.fn.readfile(path), "\n")
assert(working_contents:find("delete two", 1, true) and not working_contents:find("delete one", 1, true))
assert(git("diff", "--", "sample.lua") ~= "")
wait_refresh("partial discard did not refresh")

unstaged = pane("unstaged")
vim.api.nvim_win_set_cursor(unstaged.win, { assert(hunk_row("unstaged")), 0 })
assert(patch.action("delete", { confirm = false }))
wait_apply("final discard did not apply")
assert(git("diff", "--", "sample.lua") == "")
patch.close()
assert(not patch.get())
print("PASS patch.lua")
