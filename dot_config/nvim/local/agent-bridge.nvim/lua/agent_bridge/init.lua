local M = {}

local context_builder = require("agent_bridge.context")
local prompt = require("agent_bridge.prompt")
local targets = require("agent_bridge.targets")
local transport = require("agent_bridge.transport")

local config = {
  tmux = {
    process_name = { "pi", "opencode", "cursor-agent", "claude" },
  },
  targets = {
    remember_target = false,
  },
  prompt = {
    width_ratio = 0.6,
    min_height = 8,
    max_height = 18,
    title = " Compose to Agent ",
  },
}

local setup_done = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Agent" })
end

local function dispatch(builder, opts)
  local payload, err = builder(opts)
  if not payload or payload == "" then
    notify(err or "no context available", vim.log.levels.WARN)
    return false
  end
  if opts and opts.interactive_prompt then
    prompt.open(payload)
    return true
  end
  transport.send(payload, opts)
  return true
end

local function send_context(kind, opts)
  opts = vim.deepcopy(opts or {})
  if kind == "buffers" then
    opts.use_all_buffers = true
    return dispatch(context_builder.build_file, opts)
  elseif kind == "diagnostics" or kind == "errors" then
    if kind == "errors" then
      opts.severity = vim.diagnostic.severity.ERROR
    end
    return dispatch(context_builder.build_diagnostics, opts)
  elseif kind ~= nil and kind ~= "file" and kind ~= "selection" then
    notify("Unknown context kind: " .. tostring(kind), vim.log.levels.WARN)
    return false
  end
  return dispatch(context_builder.build_file, opts)
end

function M.send(message, opts, done)
  opts = opts or {}
  if type(message) ~= "string" or vim.trim(message) == "" then
    notify("no message to send", vim.log.levels.WARN)
    if done then
      done(false)
    end
    return false
  end
  if opts.interactive_prompt then
    prompt.open(message)
    return true
  end
  transport.send(message, opts, done)
  return true
end

function M.compose(message)
  prompt.open(message or "")
  return true
end

M.context = {}

function M.context.send(kind, opts)
  return send_context(kind or "file", opts)
end

function M.context.compose(kind, opts)
  opts = vim.tbl_extend("force", opts or {}, { interactive_prompt = true })
  return send_context(kind or "file", opts)
end

function M.context.send_visual()
  return send_context("selection", context_builder.visual_selection_opts())
end

function M.context.compose_visual()
  local opts = context_builder.visual_selection_opts()
  opts.interactive_prompt = true
  return send_context("selection", opts)
end

M.prompt = {
  resume = prompt.resume,
}

M.target = {
  select = targets.select,
  clear = targets.clear,
}

local function command_opts(command)
  local opts = {}
  if command.range == 2 then
    opts.range = 2
    opts.line1 = command.line1
    opts.line2 = command.line2
    opts.selection_kind = "line"
  end
  return opts
end

local function command_dispatch(command)
  local words = vim.split(vim.trim(command.args), "%s+", { trimempty = true })
  local action = words[1] or "compose"
  if action == "compose" or action == "send" then
    local kind = words[2] or "file"
    local opts = command_opts(command)
    opts.interactive_prompt = action == "compose"
    send_context(kind, opts)
  elseif action == "resume" then
    prompt.resume()
  elseif action == "target" then
    if words[2] == "clear" then
      targets.clear()
    elseif words[2] == nil or words[2] == "select" then
      targets.select()
    else
      notify("Usage: :Agent target [select|clear]", vim.log.levels.WARN)
    end
  elseif action == "help" then
    notify("compose [file|buffers|diagnostics|errors] · send [...] · resume · target [select|clear]")
  else
    notify("Unknown :Agent subcommand: " .. action, vim.log.levels.WARN)
  end
end

local function complete(arglead, cmdline, cursorpos)
  local before = cmdline:sub(1, cursorpos)
  local args = before:gsub("^%s*Agent!?%s*", "")
  local words = vim.split(args, "%s+", { trimempty = true })
  local trailing = before:sub(-1):match("%s") ~= nil
  local choices
  if #words == 0 or (#words == 1 and not trailing) then
    choices = { "compose", "send", "resume", "target", "help" }
  elseif (words[1] == "compose" or words[1] == "send") and (#words == 1 or (#words == 2 and not trailing)) then
    choices = { "file", "buffers", "diagnostics", "errors" }
  elseif words[1] == "target" and (#words == 1 or (#words == 2 and not trailing)) then
    choices = { "select", "clear" }
  else
    choices = {}
  end
  return vim.tbl_filter(function(item) return vim.startswith(item, arglead) end, choices)
end

local function create_command()
  vim.api.nvim_create_user_command("Agent", command_dispatch, {
    desc = "Compose and send context to an agent",
    nargs = "*",
    range = true,
    complete = complete,
  })
end

function M.setup(opts)
  if setup_done then
    return M
  end
  config = vim.tbl_deep_extend("force", config, opts or {})
  targets.setup(vim.tbl_deep_extend("force", {}, config.targets, { tmux = config.tmux }))
  prompt.setup(config.prompt, transport.send)
  context_builder.setup({ prompt_buffer = prompt.buffer })
  require("agent_bridge.server").setup()
  create_command()
  setup_done = true
  return M
end

return M
