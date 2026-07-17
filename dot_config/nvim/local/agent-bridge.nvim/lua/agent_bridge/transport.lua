local M = {}

local targets = require("agent_bridge.targets")
local util = require("agent_bridge.util")

local function copy_to_clipboard(message)
  vim.fn.setreg("+", message)
end

local function tmux_send_keys(target, ...)
  local command = { "tmux", "send-keys", "-t", target }
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    table.insert(command, arg)
  end
  local _, err = util.run(command)
  return err == nil
end

local function send_to_tmux(message, opts, done)
  opts = opts or {}
  done = done or function() end
  local submit = opts.submit == true
  local switch_to_target = opts.switch_to_target
  if switch_to_target == nil then
    switch_to_target = true
  end

  targets.resolve({}, function(target, target_err)
    if not target then
      if target_err == "target selection cancelled" then
        done(false)
        return
      end
      copy_to_clipboard(message)
      vim.notify(target_err .. ", copied to clipboard", vim.log.levels.WARN)
      done(false)
      return
    end

    local temp_file = vim.fn.tempname()
    local file = io.open(temp_file, "w")
    if not file then
      copy_to_clipboard(message)
      vim.notify("failed to create temp file, copied to clipboard", vim.log.levels.ERROR)
      done(false)
      return
    end
    file:write(message)
    file:close()

    local paste_cmd = string.format(
      "tmux load-buffer %s \\; paste-buffer -p -t %s \\; delete-buffer",
      vim.fn.shellescape(temp_file),
      vim.fn.shellescape(target.pane_id)
    )
    vim.fn.system(paste_cmd)
    vim.fn.delete(temp_file)

    local ok = vim.v.shell_error == 0
    if ok and submit then
      ok = tmux_send_keys(target.pane_id, "Enter")
    end

    if not ok then
      copy_to_clipboard(message)
      vim.notify("failed to send to " .. target.pane_id .. ", copied to clipboard", vim.log.levels.WARN)
      done(false)
      return
    end

    if not switch_to_target then
      vim.notify(submit and ("sent and submitted to " .. targets.label(target)) or ("sent message to " .. targets.label(target)))
      done(true)
      return
    end

    local _, focus_err = util.run({ "tmux", "select-pane", "-t", target.pane_id })
    if focus_err then
      vim.notify("message staged, but failed to focus " .. target.pane_id .. ": " .. focus_err, vim.log.levels.WARN)
    end
    done(true)
  end)
end

local function prepare_herdr_text(message)
  if message:find("[\r\n]") then
    return "\27[200~" .. message .. "\27[201~"
  end
  return message
end

local function send_to_herdr(message, opts, done)
  opts = opts or {}
  done = done or function() end
  local submit = opts.submit == true
  local switch_to_target = opts.switch_to_target
  if switch_to_target == nil then
    switch_to_target = true
  end

  targets.resolve({}, function(target, target_err)
    if not target then
      if target_err == "target selection cancelled" then
        done(false)
        return
      end
      copy_to_clipboard(message)
      vim.notify(target_err .. ", copied to clipboard", vim.log.levels.WARN)
      done(false)
      return
    end

    local _, send_err = util.herdr("agent", "send", target.pane_id, prepare_herdr_text(message))
    if send_err then
      copy_to_clipboard(message)
      vim.notify("failed to send to " .. target.pane_id .. ": " .. send_err .. ", copied to clipboard", vim.log.levels.ERROR)
      done(false)
      return
    end

    if submit then
      local _, submit_err = util.herdr("pane", "send-keys", target.pane_id, "enter")
      if submit_err then
        vim.notify("message staged, but submission failed: " .. submit_err, vim.log.levels.WARN)
        done(true)
        return
      end
    end

    if not switch_to_target then
      vim.notify(submit and ("sent and submitted to " .. targets.label(target)) or ("sent message to " .. targets.label(target)))
      done(true)
      return
    end

    local _, focus_err = util.herdr("agent", "focus", target.pane_id)
    if focus_err then
      vim.notify("message staged, but failed to focus " .. target.pane_id .. ": " .. focus_err, vim.log.levels.WARN)
    end
    done(true)
  end)
end

function M.send(message, opts, done)
  if targets.in_herdr() then
    send_to_herdr(message, opts, done)
  else
    send_to_tmux(message, opts, done)
  end
end

return M
