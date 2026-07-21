local M = {}

local config = {
  width_ratio = 0.6,
  min_height = 8,
  max_height = 18,
  title = " Compose to Agent ",
}

local send_message
local composer

function M.setup(opts, sender)
  config = vim.tbl_deep_extend("force", config, opts or {})
  send_message = sender
end

local function instance()
  if composer then
    return composer
  end
  composer = require("agent_bridge.input").new({
    title = config.title,
    footer = " Alt-S stage · Ctrl-S send · Ctrl-X hide ",
    width = config.width_ratio,
    min_height = config.min_height,
    max_height = config.max_height,
    persistent = true,
    accept_label = "Stage message",
    meta_s = { action = "stage" },
    meta_s_label = "Stage message",
    ctrl_s = { action = "submit", submit = true, switch_to_target = false },
    ctrl_s_label = "Send message",
    on_accept = function(content, action, done)
      send_message(content, action, done)
    end,
  })
  return composer
end

function M.buffer()
  return composer and composer.buffer or nil
end

function M.open(initial_content)
  if initial_content and initial_content ~= "" then
    initial_content = initial_content .. "\n\n"
  end
  instance():open(initial_content, { append = true })
end

function M.resume()
  if not composer or not composer:resume() then
    vim.notify("no prompt to resume", vim.log.levels.WARN)
  end
end

return M
