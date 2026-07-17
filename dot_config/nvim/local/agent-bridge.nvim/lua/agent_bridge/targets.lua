local M = {}

local util = require("agent_bridge.util")

local config = {
  remember_target = false,
  tmux = {
    process_name = { "pi", "opencode", "cursor-agent", "claude" },
  },
}

local pinned_target = nil

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.in_herdr()
  return vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID and vim.env.HERDR_PANE_ID ~= ""
end

local function backend()
  return M.in_herdr() and "herdr" or "tmux"
end

local function process_names()
  local names = config.tmux.process_name
  return type(names) == "table" and names or { names }
end

local function process_name_label()
  return table.concat(process_names(), "/")
end

local function matches_process(command)
  if not command or command == "" then
    return false
  end

  for _, name in ipairs(process_names()) do
    if type(name) == "string" and name ~= "" and command:match(vim.pesc(name)) then
      return true
    end
  end

  return false
end

local function herdr_candidates()
  local workspace_id = vim.env.HERDR_WORKSPACE_ID
  if not workspace_id or workspace_id == "" then
    return nil, "HERDR_WORKSPACE_ID is unavailable"
  end

  local output, err = util.herdr("agent", "list")
  if not output then
    return nil, "failed to list Herdr agents: " .. err
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok or type(decoded) ~= "table" then
    return nil, "failed to parse Herdr agent list"
  end

  local matches = {}
  for _, agent in ipairs((decoded.result or {}).agents or {}) do
    if agent.workspace_id == workspace_id and agent.pane_id and agent.pane_id ~= vim.env.HERDR_PANE_ID then
      agent.backend = "herdr"
      table.insert(matches, agent)
    end
  end

  local tab_id = vim.env.HERDR_TAB_ID
  table.sort(matches, function(a, b)
    local a_same_tab = a.tab_id == tab_id
    local b_same_tab = b.tab_id == tab_id
    if a_same_tab ~= b_same_tab then
      return a_same_tab
    end
    if (a.agent or "") ~= (b.agent or "") then
      return (a.agent or "") < (b.agent or "")
    end
    return a.pane_id < b.pane_id
  end)

  return matches, nil
end

local function tmux_candidates()
  local output, err = util.run({
    "tmux",
    "list-panes",
    "-F",
    "#{pane_id}\t#{pane_current_command}\t#{pane_current_path}",
  })
  if not output then
    return nil, "failed to list tmux panes: " .. err
  end

  local matches = {}
  for line in output:gmatch("[^\n]+") do
    local pane_id, command, cwd = line:match("^([^\t]+)\t([^\t]*)\t(.*)$")
    if pane_id and matches_process(command) then
      table.insert(matches, {
        backend = "tmux",
        pane_id = pane_id,
        agent = command,
        cwd = cwd,
      })
    end
  end

  table.sort(matches, function(a, b)
    if (a.agent or "") ~= (b.agent or "") then
      return (a.agent or "") < (b.agent or "")
    end
    return a.pane_id < b.pane_id
  end)

  return matches, nil
end

local function candidates()
  if M.in_herdr() then
    return herdr_candidates()
  end
  return tmux_candidates()
end

function M.label(target)
  local cwd = target.foreground_cwd or target.cwd or "?"
  local status = target.agent_status and (" [" .. target.agent_status .. "]") or ""
  return string.format(
    "%s%s %s (%s)",
    target.agent or "agent",
    status,
    vim.fn.fnamemodify(cwd, ":~:."),
    target.pane_id
  )
end

local function find_candidate(items, target)
  if not target or target.backend ~= backend() then
    return nil
  end
  for _, candidate in ipairs(items) do
    if candidate.pane_id == target.pane_id then
      return candidate
    end
  end
end

local function no_candidates_message()
  if M.in_herdr() then
    return "no coding agent found in the current Herdr workspace"
  end
  return "no pane running " .. process_name_label() .. " in the current tmux window"
end

function M.resolve(opts, callback)
  opts = opts or {}
  local items, err = candidates()
  if not items then
    callback(nil, err)
    return
  end
  if #items == 0 then
    pinned_target = nil
    callback(nil, no_candidates_message())
    return
  end

  if not opts.force_select and pinned_target then
    local remembered = find_candidate(items, pinned_target)
    if remembered then
      pinned_target = remembered
      callback(remembered)
      return
    end
    pinned_target = nil
    vim.notify("pinned agent is no longer available", vim.log.levels.WARN)
  end

  if #items == 1 then
    if opts.pin then
      pinned_target = items[1]
    end
    callback(items[1])
    return
  end

  vim.ui.select(items, {
    prompt = opts.pin and "Pin agent target" or "Send to agent",
    format_item = M.label,
  }, function(choice)
    if choice and (opts.pin or config.remember_target) then
      pinned_target = choice
    end
    callback(choice, choice and nil or "target selection cancelled")
  end)
end

function M.select()
  M.resolve({ force_select = true, pin = true }, function(target, err)
    if target then
      vim.notify("pinned agent target: " .. M.label(target))
    elseif err ~= "target selection cancelled" then
      vim.notify(err, vim.log.levels.WARN)
    end
  end)
end

function M.clear()
  if not pinned_target then
    vim.notify("no pinned agent target")
    return
  end
  pinned_target = nil
  vim.notify("cleared pinned agent target")
end

return M
