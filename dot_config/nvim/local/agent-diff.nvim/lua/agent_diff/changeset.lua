local M = {}

local git = require("agent_diff.git")
local render = require("agent_diff.render")
local ui = require("agent_diff.ui")
local watch = require("agent_diff.watch")
local active

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function emit(pattern, session)
  vim.api.nvim_exec_autocmds("User", {
    pattern = pattern,
    modeline = false,
    data = session and {
      modified_buf = session.modified_buf,
      original_buf = session.original_buf,
      revision = session.original_revision,
      layout = session.layout,
    } or nil,
  })
end

local function scratch(name, lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = filetype or ""
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "" })
  vim.bo[buf].modifiable = false
  return buf
end

local function clear_context(session)
  if valid_buf(session.modified_buf) then
    render.clear(session.modified_buf)
    vim.b[session.modified_buf].agent_diff_active = nil
    vim.b[session.modified_buf].agent_diff_context = nil
    for _, lhs in ipairs({ "<leader>b", "]f", "[f" }) do
      pcall(vim.keymap.del, "n", lhs, { buffer = session.modified_buf })
    end
  end
  if valid_buf(session.original_buf) then
    render.clear(session.original_buf)
  end
end

local function install_diff_maps(session, buf)
  local opts = { buffer = buf, silent = true }
  vim.keymap.set("n", "<leader>b", M.toggle_sidebar, vim.tbl_extend("force", opts, { desc = "Toggle diff files" }))
  vim.keymap.set("n", "]f", M.next_file, vim.tbl_extend("force", opts, { desc = "Next diff file" }))
  vim.keymap.set("n", "[f", M.prev_file, vim.tbl_extend("force", opts, { desc = "Previous diff file" }))
end

local function render_explorer(session)
  if not valid_buf(session.explorer_buf) then
    return
  end
  local lines = {}
  for index, file in ipairs(session.files) do
    local marker = index == session.index and "▸" or " "
    lines[index] = string.format("%s %s %-2s %s", marker, index == session.index and "●" or " ", file.status or "", file.path)
  end
  vim.bo[session.explorer_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.explorer_buf, 0, -1, false, lines)
  vim.bo[session.explorer_buf].modifiable = false
  if valid_win(session.explorer_win) then
    vim.api.nvim_win_set_cursor(session.explorer_win, { math.max(1, session.index), 0 })
  end
  ui.update(session)
end

local function open_sidebar(session)
  if valid_win(session.explorer_win) then
    return
  end
  local anchor = valid_win(session.modified_win) and session.modified_win or session.host_win
  if not valid_win(anchor) then
    return
  end
  vim.api.nvim_set_current_win(anchor)
  vim.cmd("topleft 34vsplit")
  session.explorer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(session.explorer_win, session.explorer_buf)
  vim.wo[session.explorer_win].number = false
  vim.wo[session.explorer_win].relativenumber = false
  vim.wo[session.explorer_win].wrap = false
  vim.wo[session.explorer_win].cursorline = true
  render_explorer(session)
  if valid_win(session.modified_win) then
    vim.api.nvim_set_current_win(session.modified_win)
  end
  ui.update(session)
end

local function close_sidebar(session)
  if valid_win(session.explorer_win) then
    pcall(vim.api.nvim_win_close, session.explorer_win, true)
  end
  session.explorer_win = nil
end

local function ensure_side(session)
  if valid_win(session.original_win) then
    vim.api.nvim_win_set_buf(session.original_win, session.original_buf)
    return
  end
  if not valid_win(session.modified_win) then
    return
  end
  vim.api.nvim_set_current_win(session.modified_win)
  vim.cmd("leftabove vsplit")
  session.original_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(session.original_win, session.original_buf)
  if valid_win(session.modified_win) then
    vim.api.nvim_set_current_win(session.modified_win)
  end
end

local function close_side(session)
  if valid_win(session.original_win) then
    pcall(vim.api.nvim_win_close, session.original_win, true)
  end
  session.original_win = nil
  if valid_win(session.modified_win) then
    vim.wo[session.modified_win].scrollbind = false
  end
end

local function compute(session, timeout)
  if session ~= active or not valid_buf(session.modified_buf) then
    return
  end
  session.modified_lines = vim.api.nvim_buf_get_lines(session.modified_buf, 0, -1, false)
  local ok, result = pcall(require("codediff.core.diff").compute_diff, session.original_lines, session.modified_lines, {
    max_computation_time_ms = timeout or 100,
    compute_moves = false,
  })
  if not ok then
    vim.notify(result, vim.log.levels.ERROR, { title = "Agent Diff" })
    return
  end
  session.diff_result = result
  if session.layout == "side-by-side" then
    ensure_side(session)
    render.side_by_side(session)
  else
    close_side(session)
    render.inline(session)
  end
  render_explorer(session)
  ui.update(session)
  emit("AgentDiffUpdated", session)
end

local function check_working_file(session, warn)
  if session.modified_revision ~= "WORKING" or not valid_buf(session.modified_buf) then
    return true
  end
  if vim.bo[session.modified_buf].modified then
    if warn and not session.external_change_notified then
      session.external_change_notified = true
      vim.notify("The file changed on disk while this buffer has unsaved edits", vim.log.levels.WARN, {
        title = "Agent Diff",
      })
    end
    return false
  end
  session.external_change_notified = false
  vim.api.nvim_buf_call(session.modified_buf, function()
    pcall(vim.cmd, "silent! checktime")
  end)
  return true
end

local function setup_external_refresh(session)
  watch.stop(session.file_watcher)
  session.file_watcher = nil
  local generation = session.generation
  local function refresh_file()
    if session ~= active or generation ~= session.generation then
      return
    end
    check_working_file(session, true)
    M.refresh({ files = true, external = true })
  end
  if session.modified_revision == "WORKING" then
    local file = session.files[session.index]
    if file then
      session.file_watcher = watch.file(session.root .. "/" .. file.path, refresh_file)
    end
  end
  local git_dir = git.git_dir(session.root)
  local dynamic_revisions = session.original_revision == "INDEX"
    or session.original_revision == "WORKING"
    or session.modified_revision == "INDEX"
    or session.modified_revision == "WORKING"
  if not session.index_watcher and git_dir and dynamic_revisions then
    session.index_watcher = watch.directory(git_dir, function()
      if session == active then
        M.refresh({ files = true, external = true })
      end
    end, 200)
  end
end

local function setup_live_refresh(session)
  if session.refresh_group then
    pcall(vim.api.nvim_del_augroup_by_id, session.refresh_group)
  end
  session.refresh_group = vim.api.nvim_create_augroup("AgentDiffChangesetRefresh", { clear = true })
  if session.modified_revision ~= "WORKING" or not valid_buf(session.modified_buf) then
    return
  end
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = session.refresh_group,
    buffer = session.modified_buf,
    callback = function()
      if session.timer then
        session.timer:stop()
      else
        session.timer = assert(vim.uv.new_timer())
      end
      session.timer:start(180, 0, vim.schedule_wrap(function()
        if session == active then
          compute(session, 100)
        end
      end))
    end,
  })
end

local function dispose_file_buffers(session)
  watch.stop(session.file_watcher)
  session.file_watcher = nil
  clear_context(session)
  if valid_buf(session.original_buf) then
    pcall(vim.api.nvim_buf_delete, session.original_buf, { force = true })
  end
  if session.modified_scratch and valid_buf(session.modified_buf) then
    pcall(vim.api.nvim_buf_delete, session.modified_buf, { force = true })
  end
  session.original_buf = nil
  session.modified_buf = nil
  session.modified_scratch = false
end

function M.select(index)
  local session = active
  if not session or #session.files == 0 then
    return
  end
  index = ((index - 1) % #session.files) + 1
  session.index = index
  session.generation = session.generation + 1
  local generation = session.generation
  local file = session.files[index]
  local old_path = file.old_path or file.path
  local new_path = file.path
  local old_lines, new_lines, new_existing_buf
  local pending = 2

  local function ready()
    pending = pending - 1
    if pending > 0 or session ~= active or generation ~= session.generation then
      return
    end
    -- Keep the layout alive while replacing scratch revision buffers. Deleting
    -- a scratch buffer that is the only buffer in a split can close that split.
    for _, win in ipairs({ session.original_win, session.modified_win }) do
      if valid_win(win) and valid_buf(session.explorer_buf) then
        vim.api.nvim_win_set_buf(win, session.explorer_buf)
      end
    end
    dispose_file_buffers(session)
    local filetype = vim.filetype.match({ filename = new_path }) or ""
    session.original_lines = old_lines or {}
    session.original_buf = scratch(
      string.format("agent-diff://%s/%s", session.original_revision, old_path),
      session.original_lines,
      filetype
    )

    if session.modified_revision == "WORKING" and vim.uv.fs_stat(session.root .. "/" .. new_path) then
      session.modified_buf = new_existing_buf or vim.fn.bufadd(session.root .. "/" .. new_path)
      vim.fn.bufload(session.modified_buf)
      session.modified_scratch = false
      new_lines = vim.api.nvim_buf_get_lines(session.modified_buf, 0, -1, false)
    else
      session.modified_buf = scratch(
        string.format("agent-diff://%s/%s", session.modified_revision, new_path),
        new_lines or {},
        filetype
      )
      session.modified_scratch = true
    end
    session.modified_lines = new_lines or {}
    if not valid_win(session.modified_win) then
      return
    end
    vim.api.nvim_win_set_buf(session.modified_win, session.modified_buf)
    vim.b[session.original_buf].agent_diff_context = {
      root = session.root,
      path = new_path,
      side = "old",
      selected_revision = session.original_revision,
      base_revision = session.original_revision,
      target_revision = session.modified_revision,
    }
    vim.b[session.modified_buf].agent_diff_active = true
    vim.b[session.modified_buf].agent_diff_context = {
      root = session.root,
      path = new_path,
      side = session.modified_revision == "WORKING" and "working" or "new",
      selected_revision = session.modified_revision,
      base_revision = session.original_revision,
      target_revision = session.modified_revision,
    }
    install_diff_maps(session, session.original_buf)
    install_diff_maps(session, session.modified_buf)
    setup_live_refresh(session)
    setup_external_refresh(session)
    compute(session, 500)
    emit("AgentDiffFile", session)
  end

  git.load_revision(session.root, old_path, session.original_revision, function(err, lines)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "Agent Diff" })
      lines = {}
    end
    old_lines = lines
    ready()
  end)
  git.load_revision(session.root, new_path, session.modified_revision, function(err, lines, bufnr)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "Agent Diff" })
      lines = {}
    end
    new_lines, new_existing_buf = lines, bufnr
    ready()
  end)
end

function M.next_file()
  if active then
    M.select(active.index + 1)
  end
end

function M.prev_file()
  if active then
    M.select(active.index - 1)
  end
end

function M.refresh(opts)
  local session = active
  if not session then
    return
  end
  opts = opts or {}
  check_working_file(session)

  local function update(files)
    if session ~= active then
      return
    end
    if files then
      if #files == 0 then
        vim.notify("No changed files", vim.log.levels.INFO, { title = "Agent Diff" })
        M.close()
        return
      end
      local current = session.files[session.index]
      local current_path = current and current.path
      session.files = files
      session.index = 1
      for index, file in ipairs(files) do
        if file.path == current_path then
          session.index = index
          break
        end
      end
    end
    M.select(session.index)
  end

  if opts.files and session.reload_files then
    session.refresh_request = (session.refresh_request or 0) + 1
    local request = session.refresh_request
    session.reload_files(function(err, files)
      vim.schedule(function()
        if session ~= active or request ~= session.refresh_request then
          return
        end
        if err then
          vim.notify(err, vim.log.levels.ERROR, { title = "Agent Diff" })
        else
          update(files)
        end
      end)
    end)
  else
    update()
  end
end

function M.toggle_sidebar()
  if not active then
    return
  end
  if valid_win(active.explorer_win) then
    close_sidebar(active)
  else
    open_sidebar(active)
  end
end

function M.set_layout(layout)
  if not active then
    return
  end
  if active.layout == layout then
    M.close()
    return
  end
  active.layout = layout
  compute(active, 100)
  emit("AgentDiffLayout", active)
end

function M.open(opts)
  opts = opts or {}
  M.close()
  local files = opts.files or {}
  if #files == 0 then
    vim.notify("No changed files", vim.log.levels.INFO, { title = "Agent Diff" })
    return
  end
  local return_buf = vim.api.nvim_get_current_buf()
  local return_bufhidden = vim.bo[return_buf].bufhidden
  vim.bo[return_buf].bufhidden = "hide"
  local host_win = vim.api.nvim_get_current_win()
  local parking_win
  if opts.park_owner then
    parking_win = vim.api.nvim_open_win(return_buf, false, {
      relative = "editor",
      width = 1,
      height = 1,
      row = 0,
      col = 0,
      style = "minimal",
      focusable = false,
      hide = true,
      noautocmd = true,
    })
    opts.park_owner.win_handle = parking_win
  end
  local explorer_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[explorer_buf].buftype = "nofile"
  vim.bo[explorer_buf].bufhidden = "hide"
  vim.bo[explorer_buf].swapfile = false
  vim.bo[explorer_buf].filetype = "AgentDiffFiles"
  pcall(vim.api.nvim_buf_set_name, explorer_buf, "agent-diff://files")

  local index = 1
  if opts.focus_file then
    for i, file in ipairs(files) do
      if file.path == opts.focus_file then
        index = i
        break
      end
    end
  end
  active = {
    kind = "changeset",
    root = opts.root,
    files = files,
    index = index,
    original_revision = opts.original_revision,
    modified_revision = opts.modified_revision,
    revision = opts.original_revision,
    layout = opts.layout or "inline",
    host_win = host_win,
    modified_win = host_win,
    return_buf = return_buf,
    return_bufhidden = return_bufhidden,
    parking_win = parking_win,
    park_owner = opts.park_owner,
    on_close = opts.on_close,
    reload_files = opts.reload_files,
    explorer_buf = explorer_buf,
    generation = 0,
    diff_result = { changes = {}, moves = {} },
  }
  local session = active
  ui.capture(session, host_win)
  ui.update(session)
  vim.keymap.set("n", "<cr>", function()
    M.select(vim.api.nvim_win_get_cursor(0)[1])
  end, { buffer = explorer_buf, silent = true, desc = "Open diff file" })
  install_diff_maps(session, explorer_buf)
  M.select(index)
  if opts.explorer ~= false and #files > 1 then
    open_sidebar(session)
  end
  emit("AgentDiffOpen", session)
  return session
end

function M.close()
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
  if session.refresh_group then
    pcall(vim.api.nvim_del_augroup_by_id, session.refresh_group)
  end
  watch.stop(session.index_watcher)
  session.index_watcher = nil
  close_side(session)
  close_sidebar(session)
  dispose_file_buffers(session)
  if valid_win(session.host_win) and valid_buf(session.return_buf) then
    vim.api.nvim_win_set_buf(session.host_win, session.return_buf)
    vim.bo[session.return_buf].bufhidden = session.return_bufhidden
    if session.park_owner then
      session.park_owner.win_handle = session.host_win
    end
    vim.api.nvim_set_current_win(session.host_win)
  end
  ui.restore(session)
  if valid_win(session.parking_win) then
    pcall(vim.api.nvim_win_close, session.parking_win, true)
  end
  if valid_buf(session.explorer_buf) then
    pcall(vim.api.nvim_buf_delete, session.explorer_buf, { force = true })
  end
  if session.on_close then
    pcall(session.on_close)
  end
  emit("AgentDiffClose", session)
end

function M.get_session(bufnr)
  if not active then
    return nil
  end
  if not bufnr
    or bufnr == active.modified_buf
    or bufnr == active.original_buf
    or bufnr == active.explorer_buf
  then
    return active
  end
end

return M
