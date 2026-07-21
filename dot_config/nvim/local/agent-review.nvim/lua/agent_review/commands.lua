local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Agent Review" })
end

local function words(args)
  return vim.split(vim.trim(args or ""), "%s+", { trimempty = true })
end

local function has(items, value)
  return vim.tbl_contains(items, value)
end

local function optional_id(items, index)
  local value = items[index]
  return value and not vim.startswith(value, "--") and value or nil
end

local function dispatch(api, command)
  local args = words(command.args)
  local action = args[1] or "list"

  if action == "list" then
    api.list({ all = has(args, "--all") })
  elseif action == "add" then
    if args[2] == "old" then
      api.add_old()
    else
      local opts = {}
      if command.range == 2 then
        opts.range = 2
        opts.line1 = command.line1
        opts.line2 = command.line2
        opts.selection_kind = "line"
      end
      api.add(opts)
    end
  elseif action == "edit" then
    api.edit(optional_id(args, 2))
  elseif action == "resolve" then
    api.resolve(optional_id(args, 2))
  elseif action == "reopen" then
    api.reopen(optional_id(args, 2))
  elseif action == "remove" then
    api.remove(optional_id(args, 2))
  elseif action == "send" then
    local submit = has(args, "--submit")
    api.send({
      all = has(args, "--all"),
      submit = submit,
      switch_to_target = not submit,
    })
  elseif action == "compose" then
    api.send({ all = has(args, "--all"), interactive_prompt = true })
  elseif action == "session" then
    local subcommand = args[2] or "list"
    if subcommand == "list" then
      api.sessions()
    elseif subcommand == "new" then
      api.session_new(table.concat(args, " ", 3))
    elseif subcommand == "switch" then
      if not args[3] then
        notify("Usage: :AgentReview session switch <id>", vim.log.levels.WARN)
      else
        api.session_switch(args[3])
      end
    elseif subcommand == "archive" then
      api.session_archive(args[3])
    elseif subcommand == "clear" then
      api.clear_session()
    else
      notify("Unknown session subcommand: " .. subcommand, vim.log.levels.WARN)
    end
  elseif action == "workspace" then
    local subcommand = args[2] or "list"
    if subcommand == "list" then
      api.workspaces()
    elseif subcommand == "clear" then
      api.clear_current()
    else
      notify("Unknown workspace subcommand: " .. subcommand, vim.log.levels.WARN)
    end
  elseif action == "prune" then
    api.prune({ include_stale = has(args, "--stale"), all = has(args, "--all") })
  elseif action == "clear" then
    if has(args, "--all") then
      api.clear()
    else
      notify("Refusing global clear without --all", vim.log.levels.WARN)
    end
  elseif action == "help" then
    notify("add [old] · list [--all] · edit/resolve/reopen/remove [id] · send/compose · session · workspace · prune · clear --all")
  else
    notify("Unknown :AgentReview subcommand: " .. action, vim.log.levels.WARN)
  end
end

local function candidates(cmdline, cursorpos)
  local before = cmdline:sub(1, cursorpos)
  local args = before:gsub("^%s*AgentReview!?%s*", "")
  local parsed = words(args)
  local trailing = before:sub(-1):match("%s") ~= nil
  local top = { "add", "list", "edit", "resolve", "reopen", "remove", "send", "compose", "session", "workspace", "prune", "clear", "help" }
  if #parsed == 0 or (#parsed == 1 and not trailing) then
    return top
  end

  local action = parsed[1]
  if action == "add" and (#parsed == 1 or (#parsed == 2 and not trailing)) then
    return { "old" }
  elseif action == "list" or action == "compose" then
    return { "--all" }
  elseif action == "send" then
    return { "--submit", "--all" }
  elseif action == "prune" then
    return { "--stale", "--all" }
  elseif action == "clear" then
    return { "--all" }
  elseif action == "workspace" then
    return { "list", "clear" }
  elseif action == "session" then
    if #parsed == 1 or (#parsed == 2 and not trailing) then
      return { "list", "new", "switch", "archive", "clear" }
    elseif parsed[2] == "switch" or parsed[2] == "archive" then
      local result = {}
      for _, session in ipairs(require("agent_review.sessions").list(nil, { include_archived = true })) do
        table.insert(result, session.id)
      end
      return result
    end
  elseif action == "edit" or action == "resolve" or action == "reopen" or action == "remove" then
    local result = {}
    for _, annotation in ipairs(require("agent_review.state").list()) do
      table.insert(result, annotation.id)
    end
    return result
  end
  return {}
end

function M.setup(api)
  vim.api.nvim_create_user_command("AgentReview", function(command)
    dispatch(api, command)
  end, {
    desc = "Manage agent review annotations",
    nargs = "*",
    range = true,
    complete = function(arglead, cmdline, cursorpos)
      return vim.tbl_filter(function(item) return vim.startswith(item, arglead) end, candidates(cmdline, cursorpos))
    end,
  })
end

return M
