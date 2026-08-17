vim.env.HERDR_ENV = "1"
vim.env.HERDR_WORKSPACE_ID = "w14"
vim.env.HERDR_TAB_ID = "w14:t3"
vim.env.HERDR_PANE_ID = "w14:p5"

local util = require("agent_bridge.util")
local original_herdr = util.herdr
util.herdr = function(...)
  local args = { ... }
  assert(args[1] == "agent" and args[2] == "list")
  return vim.json.encode({
    result = {
      agents = {
        { agent = "pi", agent_status = "idle", pane_id = "w14:p1", tab_id = "w14:t1", workspace_id = "w14" },
        { agent = "pi", agent_status = "working", pane_id = "w14:p3", tab_id = "w14:t3", workspace_id = "w14" },
        { agent = "pi", agent_status = "idle", pane_id = "w14:p4", tab_id = "w14:t4", workspace_id = "w14" },
      },
    },
  })
end

local select_calls = 0
local original_select = vim.ui.select
vim.ui.select = function()
  select_calls = select_calls + 1
end

local selected
local err
require("agent_bridge.targets").resolve({}, function(target, target_err)
  selected = target
  err = target_err
end)

assert(err == nil)
assert(selected and selected.pane_id == "w14:p3", "expected the unique same-tab agent to be selected")
assert(select_calls == 0, "unique same-tab agent should not open the target picker")

vim.ui.select = function(items, _, callback)
  select_calls = select_calls + 1
  callback(items[3])
end
selected = nil
require("agent_bridge.targets").resolve({ force_select = true }, function(target)
  selected = target
end)
assert(select_calls == 1, "explicit target selection should still open the picker")
assert(selected and selected.pane_id == "w14:p4")

vim.ui.select = original_select
util.herdr = original_herdr
