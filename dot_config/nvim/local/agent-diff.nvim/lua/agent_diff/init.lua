local M = {}

local git = require("agent_diff.git")
local render = require("agent_diff.render")
local ui = require("agent_diff.ui")
local watch = require("agent_diff.watch")

local config = {
  debounce_ms = 180,
  live_timeout_ms = 100,
  initial_timeout_ms = 500,
  default_revision = "HEAD",
}
local active
local initialized = false

local function changeset()
  return require("agent_diff.changeset")
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Agent Diff" })
end

local function emit(pattern, session)
  vim.api.nvim_exec_autocmds("User", {
    pattern = pattern,
    modeline = false,
    data = session and {
      modified_buf = session.modified_buf,
      original_buf = session.original_buf,
      revision = session.revision,
      layout = session.layout,
    } or nil,
  })
end

local function valid_buf(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function set_original_lines(session, lines)
  vim.bo[session.original_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.original_buf, 0, -1, false, #lines > 0 and lines or { "" })
  vim.bo[session.original_buf].modifiable = false
end

local function compute(session, timeout)
  if session ~= active or not valid_buf(session.modified_buf) then
    return false
  end
  session.modified_lines = vim.api.nvim_buf_get_lines(session.modified_buf, 0, -1, false)
  local ok, result = pcall(require("codediff.core.diff").compute_diff, session.original_lines, session.modified_lines, {
    max_computation_time_ms = timeout,
    compute_moves = false,
    ignore_trim_whitespace = false,
  })
  if not ok then
    notify(result, vim.log.levels.ERROR)
    return false
  end
  session.diff_result = result
  if result.hit_timeout and not session.timeout_notified then
    session.timeout_notified = true
    notify("Character refinement reached its time budget; showing the available diff", vim.log.levels.WARN)
  end
  if session.layout == "side-by-side" then
    render.side_by_side(session)
  else
    render.inline(session)
  end
  ui.update(session)
  emit("AgentDiffUpdated", session)
  return true
end

local function close_side(session)
  if session.layout ~= "side-by-side" then
    return
  end
  session.closing_window = true
  if valid_win(session.modified_win) then
    vim.wo[session.modified_win].scrollbind = false
    vim.wo[session.modified_win].cursorbind = false
  end
  if valid_win(session.original_win) then
    pcall(vim.api.nvim_win_close, session.original_win, true)
  end
  session.original_win = nil
  session.closing_window = false
end

local function open_side(session)
  if session.layout == "side-by-side" and valid_win(session.original_win) then
    return
  end
  render.clear(session.modified_buf)
  session.modified_win = vim.fn.bufwinid(session.modified_buf)
  if session.modified_win == -1 then
    notify("Working buffer is not visible", vim.log.levels.WARN)
    return
  end
  vim.api.nvim_set_current_win(session.modified_win)
  vim.cmd("leftabove vsplit")
  session.original_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(session.original_win, session.original_buf)
  session.layout = "side-by-side"
  render.side_by_side(session)
  ui.update(session)
end

local function check_working_file(session, warn)
  if not valid_buf(session.modified_buf) then
    return false
  end
  if vim.bo[session.modified_buf].modified then
    if warn and not session.external_change_notified then
      session.external_change_notified = true
      notify("The file changed on disk while this buffer has unsaved edits", vim.log.levels.WARN)
    end
    return false
  end
  vim.api.nvim_buf_call(session.modified_buf, function()
    pcall(vim.cmd, "silent! checktime")
  end)
  return true
end

local function start_disk_watchers(session)
  local function refresh_working()
    if session ~= active then
      return
    end
    if not check_working_file(session, true) then
      return
    end
    session.external_change_notified = false
    compute(session, config.live_timeout_ms)
  end
  session.file_watcher = watch.file(session.root .. "/" .. session.path, refresh_working)
  local git_dir = git.git_dir(session.root)
  if session.revision == "INDEX" and git_dir then
    session.index_watcher = watch.file(git_dir .. "/index", function()
      if session == active then
        M.refresh({ reload = true })
      end
    end)
  end
end

local function start_autocmds(session)
  session.group = vim.api.nvim_create_augroup("AgentDiffSession", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = session.group,
    buffer = session.modified_buf,
    callback = function()
      if session ~= active then
        return
      end
      if session.timer then
        session.timer:stop()
      else
        session.timer = assert(vim.uv.new_timer())
      end
      session.timer:start(config.debounce_ms, 0, vim.schedule_wrap(function()
        if session == active then
          compute(session, config.live_timeout_ms)
        end
      end))
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = session.group,
    buffer = session.modified_buf,
    callback = function()
      if session == active then
        vim.schedule(M.close)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = session.group,
    callback = function(event)
      if session ~= active or session.closing_window then
        return
      end
      if tonumber(event.match) == session.original_win then
        vim.schedule(function()
          if session == active then
            session.original_win = nil
            session.layout = "inline"
            compute(session, config.live_timeout_ms)
            emit("AgentDiffLayout", session)
          end
        end)
      end
    end,
  })
end

function M.open(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local context, err = git.context(bufnr)
  if not context then
    notify(err, vim.log.levels.WARN)
    return nil
  end
  local revision = opts.revision or config.default_revision

  if active then
    M.close()
  end

  local original_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[original_buf].buftype = "nofile"
  vim.bo[original_buf].bufhidden = "hide"
  vim.bo[original_buf].swapfile = false
  vim.bo[original_buf].filetype = vim.bo[bufnr].filetype
  pcall(vim.api.nvim_buf_set_name, original_buf, string.format("agent-diff://%s/%s", revision, context.relative_path))

  local session = {
    modified_buf = bufnr,
    modified_win = vim.fn.bufwinid(bufnr),
    original_buf = original_buf,
    original_win = nil,
    original_lines = {},
    modified_lines = {},
    diff_result = { changes = {}, moves = {} },
    revision = revision,
    root = context.root,
    path = context.relative_path,
    layout = opts.layout or "inline",
    generation = 1,
  }
  active = session
  ui.capture(session, session.modified_win)
  ui.update(session)
  vim.b[original_buf].agent_diff_context = {
    root = context.root,
    path = context.relative_path,
    side = "old",
    selected_revision = revision,
    base_revision = revision,
    target_revision = "WORKING",
  }
  vim.b[bufnr].agent_diff_active = true
  vim.b[bufnr].agent_diff_context = {
    root = context.root,
    path = context.relative_path,
    side = "working",
    selected_revision = "WORKING",
    base_revision = revision,
    target_revision = "WORKING",
  }
  for _, target_buf in ipairs({ original_buf, bufnr }) do
    vim.keymap.set("n", "<leader>b", M.toggle_sidebar, {
      buffer = target_buf,
      silent = true,
      desc = "Toggle diff files",
    })
    vim.keymap.set("n", "?", require("agent_diff.help").diff, {
      buffer = target_buf,
      silent = true,
      desc = "Agent Diff help",
    })
  end
  start_autocmds(session)
  start_disk_watchers(session)

  git.load(context, revision, function(load_err, lines)
    if session ~= active then
      return
    end
    if load_err then
      notify(load_err, vim.log.levels.ERROR)
      M.close()
      return
    end
    session.original_lines = lines
    set_original_lines(session, lines)
    compute(session, config.initial_timeout_ms)
    if opts.layout == "side-by-side" then
      open_side(session)
    end
    emit("AgentDiffOpen", session)
  end)
  return session
end

local function open_mode(layout, revision)
  revision = revision or config.default_revision
  local bufnr = vim.api.nvim_get_current_buf()
  local in_active = active and (active.modified_buf == bufnr or active.original_buf == bufnr)
  if in_active and active.layout == layout and active.revision == revision then
    M.close()
    return nil
  end
  if in_active then
    bufnr = active.modified_buf
  end
  return M.open({ bufnr = bufnr, revision = revision, layout = layout })
end

function M.inline(revision)
  local session = changeset().get_session()
  if session then
    changeset().set_layout("inline")
    return changeset().get_session()
  end
  return open_mode("inline", revision)
end

function M.side_by_side(revision)
  local session = changeset().get_session()
  if session then
    changeset().set_layout("side-by-side")
    return changeset().get_session()
  end
  return open_mode("side-by-side", revision)
end

function M.open_side(revision)
  return M.side_by_side(revision)
end

function M.toggle()
  local multi = changeset().get_session()
  if multi then
    changeset().set_layout(multi.layout == "inline" and "side-by-side" or "inline")
    return changeset().get_session()
  end
  if not active then
    return M.open()
  end
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= active.modified_buf and current_buf ~= active.original_buf then
    return M.open({ bufnr = current_buf })
  end
  if active.layout == "inline" then
    open_side(active)
  else
    close_side(active)
    active.layout = "inline"
    compute(active, config.live_timeout_ms)
  end
  emit("AgentDiffLayout", active)
  return active
end

function M.refresh(opts)
  if changeset().get_session() then
    return changeset().refresh(opts)
  end
  if not active then
    return M.open(opts)
  end
  opts = opts or {}
  check_working_file(active)
  if opts.reload then
    local context = { root = active.root, path = active.root .. "/" .. active.path, relative_path = active.path }
    git.load(context, active.revision, function(err, lines)
      if active and not err then
        active.original_lines = lines
        set_original_lines(active, lines)
        compute(active, config.initial_timeout_ms)
      elseif err then
        notify(err, vim.log.levels.ERROR)
      end
    end)
    return active
  end
  compute(active, config.initial_timeout_ms)
  return active
end

function M.close()
  if changeset().get_session() then
    return changeset().close()
  end
  local session = active
  if not session then
    return
  end
  active = nil
  if session.timer then
    session.timer:stop()
    if not session.timer:is_closing() then
      session.timer:close()
    end
  end
  if session.group then
    pcall(vim.api.nvim_del_augroup_by_id, session.group)
  end
  watch.stop(session.file_watcher)
  watch.stop(session.index_watcher)
  close_side(session)
  render.clear(session.modified_buf)
  render.clear(session.original_buf)
  if valid_buf(session.modified_buf) then
    vim.b[session.modified_buf].agent_diff_active = nil
    vim.b[session.modified_buf].agent_diff_context = nil
    pcall(vim.keymap.del, "n", "<leader>b", { buffer = session.modified_buf })
    pcall(vim.keymap.del, "n", "?", { buffer = session.modified_buf })
  end
  if valid_buf(session.original_buf) then
    pcall(vim.api.nvim_buf_delete, session.original_buf, { force = true })
  end
  ui.restore(session)
  emit("AgentDiffClose", session)
end

function M.get_session(bufnr)
  local multi = changeset().get_session(bufnr)
  if multi then
    return multi
  end
  if not active then
    return nil
  end
  if not bufnr or bufnr == active.modified_buf or bufnr == active.original_buf then
    return active
  end
  return nil
end

function M.open_changeset(opts)
  if active then
    M.close()
  end
  return changeset().open(opts)
end

function M.next_file()
  return changeset().next_file()
end

function M.prev_file()
  return changeset().prev_file()
end

function M.patch()
  return require("agent_diff.patch").open()
end

function M.toggle_sidebar()
  if changeset().get_session() then
    return changeset().toggle_sidebar()
  end
  local session = active
  if not session then
    return
  end
  local function open_files(files)
    local focus = session.path
    local opts = {
      root = session.root,
      files = files,
      focus_file = focus,
      original_revision = session.revision,
      modified_revision = "WORKING",
      layout = session.layout,
      explorer = true,
    }
    M.close()
    changeset().open(opts)
  end
  local codediff_git = require("codediff.core.git")
  if session.revision == "INDEX" then
    codediff_git.get_status(session.root, function(err, result)
      if err then
        return notify(err, vim.log.levels.ERROR)
      end
      vim.schedule(function()
        open_files(result.unstaged)
      end)
    end)
  else
    codediff_git.get_diff_revision(session.revision, session.root, function(err, result)
      if err then
        return notify(err, vim.log.levels.ERROR)
      end
      vim.schedule(function()
        open_files(result.unstaged)
      end)
    end)
  end
end

function M.setup(opts)
  if initialized then
    return
  end
  initialized = true
  config = vim.tbl_deep_extend("force", config, opts or {})
  render.setup()
  ui.setup()
  pcall(vim.api.nvim_del_user_command, "CodeDiff")

  vim.api.nvim_create_user_command("AgentDiff", function(command)
    M.inline(command.args ~= "" and command.args or nil)
  end, { nargs = "?", desc = "Toggle an inline Agent Diff" })
  vim.api.nvim_create_user_command("AgentDiffSide", function(command)
    M.side_by_side(command.args ~= "" and command.args or nil)
  end, { nargs = "?", desc = "Toggle a side-by-side Agent Diff" })
  vim.api.nvim_create_user_command("AgentDiffToggle", M.toggle, { desc = "Switch Agent Diff layout" })
  vim.api.nvim_create_user_command("AgentDiffClose", M.close, { desc = "Close Agent Diff" })
  vim.api.nvim_create_user_command("AgentDiffRefresh", function()
    M.refresh({ reload = true })
  end, { desc = "Reload and refresh Agent Diff" })
  vim.api.nvim_create_user_command("AgentPatch", M.patch, { desc = "Toggle the staged/unstaged patch workspace" })
end

return M
