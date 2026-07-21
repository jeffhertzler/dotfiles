local M = {}

local function location(capture)
  local target = capture.target
  local side = string.upper(target.side or "working")
  local range = target.start_line == target.end_line
      and tostring(target.start_line)
    or string.format("%d–%d", target.start_line, target.end_line)
  local file = vim.fn.fnamemodify(target.file, ":t")
  return string.format("%s %s:%s", side, file, range)
end

function M.open(opts)
  local verb = opts.editing and "Edit comment" or "Comment"
  local instance = require("agent_bridge.input").new({
    title = string.format(" %s · %s ", verb, location(opts.capture)),
    footer = " Ctrl-S save · q cancel ",
    width = opts.width or 0.5,
    min_width = 48,
    min_height = 1,
    max_height = opts.max_height or 8,
    persistent = false,
    accept_label = "Save comment",
    meta_s = { action = "save" },
    meta_s_label = "Save comment",
    ctrl_s = { action = "save" },
    ctrl_s_label = "Save comment",
    on_accept = function(body, _, done)
      local result = opts.on_accept(body)
      done(result ~= false and result ~= nil)
    end,
  })
  instance:open(opts.initial or "")
  return instance
end

return M
