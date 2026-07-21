local path = assert(vim.env.AGENT_DIFF_TEST_FILE)
local root = vim.fs.dirname(path)
local function git(...)
  local result = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout or "")
end

-- Turn the fixture's working changes into a second commit, then create a stash
-- so every revision-oriented DiffPopup action has something real to resolve.
git("add", ".")
git("commit", "-qm", "second")
local head = git("rev-parse", "HEAD")
local parent = git("rev-parse", "HEAD^")
vim.fn.writefile({ "local stashed_name = 3", "keep", "added", "stash" }, path)
git("stash", "push", "-qm", "agent diff test")
local stash = git("stash", "list", "--format=%gd: %s")

require("neogit").setup({
  kind = "replace",
  diff_viewer = "codediff",
  integrations = { codediff = true },
})
require("agent_diff.neogit").setup()
vim.cmd.edit(vim.fn.fnameescape(path))
vim.cmd("Neogit")
assert(vim.wait(10000, function()
  return vim.bo.filetype == "NeogitStatus"
end, 20))

local function verify(section, item, predicate, label)
  require("agent_diff.neogit").open(section, item)
  assert(vim.wait(10000, function()
    local session = require("agent_diff").get_session()
    return session and session.modified_buf and session.diff_result and predicate(session)
  end, 20), label .. " did not resolve")
  local session = assert(require("agent_diff").get_session())
  assert(session.parking_win and vim.api.nvim_win_get_config(session.parking_win).hide)
  assert(#vim.api.nvim_list_tabpages() == 1)
  require("agent_diff").close()
  assert(vim.wait(3000, function()
    return vim.bo.filetype == "NeogitStatus"
  end, 20), label .. " did not restore Neogit")
end

-- dh: selected commit to HEAD.
verify("range", parent .. "..HEAD", function(session)
  return session.original_revision == parent and session.modified_revision == "HEAD" and #session.files == 2
end, "dh")

-- dr: symmetric range, resolved through the merge base.
verify("range", parent .. "...HEAD", function(session)
  return session.original_revision == parent and session.modified_revision == head and #session.files == 2
end, "dr")

-- dc: one selected commit, shown against its first parent.
verify("commit", head .. " second", function(session)
  return session.original_revision == head .. "^" and session.modified_revision == head and #session.files == 2
end, "dc")

-- dt: selected stash, also shown against its first parent.
verify("stashes", stash, function(session)
  return session.original_revision:sub(-1) == "^"
    and session.modified_revision ~= "WORKING"
    and #session.files >= 1
end, "dt")

-- dw: the complete worktree, including all currently modified tracked files.
vim.fn.writefile({ "local working_name = 4", "keep", "added", "working" }, path)
vim.fn.writefile({ "second working" }, root .. "/second.txt")
verify("worktree", nil, function(session)
  return session.original_revision == "HEAD" and session.modified_revision == "WORKING" and #session.files == 2
end, "dw")

print("PASS revisions.lua")
