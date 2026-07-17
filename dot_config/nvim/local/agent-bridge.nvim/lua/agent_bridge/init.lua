local M = {}

local context = require("agent_bridge.context")
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
    height_ratio = 0.35,
    title = " Compose to Agent ",
  },
}

local setup_done = false

local function dispatch(builder, opts)
  local payload, err = builder(opts)
  if not payload or payload == "" then
    vim.notify(err or "no context available", vim.log.levels.WARN)
    return
  end

  if opts and opts.interactive_prompt then
    prompt.open(payload)
  else
    transport.send(payload)
  end
end

function M.send_file(opts)
  dispatch(context.build_file, opts or {})
end

function M.compose_visual()
  local opts = context.visual_selection_opts()
  opts.interactive_prompt = true
  M.send_file(opts)
end

function M.send_visual()
  M.send_file(context.visual_selection_opts())
end

function M.send_diagnostics(opts)
  dispatch(context.build_diagnostics, opts or {})
end

function M.resume_prompt()
  prompt.resume()
end

function M.select_target()
  targets.select()
end

function M.clear_target()
  targets.clear()
end

local function create_commands()
  vim.api.nvim_create_user_command("AgentBridge", function(opts)
    M.send_file(opts)
  end, { range = true })

  vim.api.nvim_create_user_command("AgentBridgeInteractive", function(opts)
    opts.interactive_prompt = true
    M.send_file(opts)
  end, { range = true })

  vim.api.nvim_create_user_command("AgentBridgeAll", function(opts)
    opts.use_all_buffers = true
    M.send_file(opts)
  end, { range = true })

  vim.api.nvim_create_user_command("AgentBridgeAllInteractive", function(opts)
    opts.use_all_buffers = true
    opts.interactive_prompt = true
    M.send_file(opts)
  end, { range = true })

  vim.api.nvim_create_user_command("AgentBridgeDiagnostics", function(opts)
    M.send_diagnostics(opts)
  end, {})

  vim.api.nvim_create_user_command("AgentBridgeDiagnosticsAll", function(opts)
    opts.use_all_buffers = true
    M.send_diagnostics(opts)
  end, {})

  vim.api.nvim_create_user_command("AgentBridgeDiagnosticsErrors", function(opts)
    opts.severity = vim.diagnostic.severity.ERROR
    M.send_diagnostics(opts)
  end, {})

  vim.api.nvim_create_user_command("AgentBridgeDiagnosticsErrorsAll", function(opts)
    opts.severity = vim.diagnostic.severity.ERROR
    opts.use_all_buffers = true
    M.send_diagnostics(opts)
  end, {})

  vim.api.nvim_create_user_command("AgentBridgeResume", function()
    M.resume_prompt()
  end, {})

  vim.api.nvim_create_user_command("AgentBridgeTarget", function()
    M.select_target()
  end, {})

  vim.api.nvim_create_user_command("AgentBridgeTargetClear", function()
    M.clear_target()
  end, {})
end

function M.setup(opts)
  if setup_done then
    return M
  end

  config = vim.tbl_deep_extend("force", config, opts or {})
  targets.setup(vim.tbl_deep_extend("force", {}, config.targets, { tmux = config.tmux }))
  prompt.setup(config.prompt, transport.send)
  context.setup({ prompt_buffer = prompt.buffer })
  create_commands()
  setup_done = true
  return M
end

return M
