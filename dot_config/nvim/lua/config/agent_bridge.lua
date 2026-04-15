local M = {}

local config = {
  tmux = {
    process_name = { "pi", "opencode", "cursor-agent", "claude" },
  },
  prompt = {
    width_ratio = 0.6,
    height_ratio = 0.35,
    title = " Compose to Agent ",
  },
}

local state = {
  setup_done = false,
  prompt_buffer = nil,
  prompt_window = nil,
  prompt_callback = nil,
  prompt_cursor = nil,
  prompt_insert_mode = false,
}

local function process_names()
  local names = config.tmux.process_name
  return type(names) == "table" and names or { names }
end

local function process_name_label()
  return table.concat(process_names(), "/")
end

local function matches_process(cmd)
  if not cmd or cmd == "" then
    return false
  end

  for _, name in ipairs(process_names()) do
    if type(name) == "string" and name ~= "" and cmd:match(vim.pesc(name)) then
      return true
    end
  end

  return false
end

local function target_buf()
  local current = vim.api.nvim_get_current_buf()
  if current ~= state.prompt_buffer and vim.bo[current].buftype == "" and vim.api.nvim_buf_get_name(current) ~= "" then
    return current
  end

  local best_buf = nil
  local latest_lastused = -1
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if buf ~= state.prompt_buffer and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      local info = vim.fn.getbufinfo(buf)[1]
      local lastused = info and info.lastused or 0
      if lastused > latest_lastused then
        latest_lastused = lastused
        best_buf = buf
      end
    end
  end

  return best_buf or current
end

local function current_file(buf)
  local path = vim.api.nvim_buf_get_name(buf or target_buf())
  if path == "" then
    return ""
  end
  return vim.fn.fnamemodify(path, ":~:.")
end

local function visual_selection_opts()
  local mode = vim.fn.mode()
  local line1 = vim.fn.getpos("v")[2]
  local col1 = vim.fn.getpos("v")[3]
  local line2 = vim.fn.getcurpos()[2]
  local col2 = vim.fn.getcurpos()[3]

  if line1 > line2 or (line1 == line2 and col1 > col2) then
    line1, line2 = line2, line1
    col1, col2 = col2, col1
  end

  return {
    range = 2,
    line1 = line1,
    col1 = col1,
    line2 = line2,
    col2 = col2,
    selection_kind = mode == "V" and "line" or mode == "\22" and "block" or "char",
  }
end

local function format_file_context(file, opts)
  if opts.range ~= 2 then
    return "@" .. file
  end

  if opts.selection_kind == "char" or opts.selection_kind == "block" then
    return string.format("%s:L%d:C%d-L%d:C%d", file, opts.line1, opts.col1, opts.line2, opts.col2)
  end

  return string.format("@%s#L%d-%d", file, opts.line1, opts.line2)
end

local function build_file_context(opts)
  opts = opts or {}

  if opts.use_all_buffers then
    local buffers = {}
    local current = current_file()

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
        local name = vim.api.nvim_buf_get_name(buf)
        local relative = vim.fn.fnamemodify(name, ":~:.")
        if
          relative ~= ""
          and vim.bo[buf].buftype == ""
          and vim.fn.filereadable(name) == 1
          and not relative:match("^term://")
          and not relative:match("^%[")
        then
          if relative == current and opts.range == 2 then
            table.insert(buffers, format_file_context(relative, opts))
          else
            table.insert(buffers, "@" .. relative)
          end
        end
      end
    end

    return table.concat(buffers, " "), "no file context available"
  end

  local file = current_file()
  if file == "" then
    return nil, "no file context available"
  end

  return format_file_context(file, opts), nil
end

local function build_diagnostics_context(opts)
  opts = opts or {}

  local diagnostics = opts.use_all_buffers and vim.diagnostic.get() or vim.diagnostic.get(target_buf())
  if opts.severity then
    diagnostics = vim.tbl_filter(function(item)
      return item.severity == opts.severity
    end, diagnostics)
  end

  if #diagnostics == 0 then
    if opts.severity then
      local severity = vim.diagnostic.severity[opts.severity]:lower()
      if opts.use_all_buffers then
        return nil, "no " .. severity .. " diagnostics found"
      end
      return nil, "no " .. severity .. " diagnostics in current buffer"
    end

    if opts.use_all_buffers then
      return nil, "no diagnostics found"
    end
    return nil, "no diagnostics in current buffer"
  end

  local grouped = {}
  for _, item in ipairs(diagnostics) do
    local name = vim.api.nvim_buf_get_name(item.bufnr)
    local relative = vim.fn.fnamemodify(name, ":~:.")
    if relative ~= "" and vim.bo[item.bufnr].buftype == "" and item.bufnr ~= state.prompt_buffer then
      grouped[relative] = grouped[relative] or {}
      table.insert(grouped[relative], item)
    end
  end

  local title = "# Diagnostics"
  if opts.severity then
    title = "# " .. vim.diagnostic.severity[opts.severity] .. " Diagnostics"
  end
  if opts.use_all_buffers then
    title = title .. " (All Buffers)"
  end

  local out = { title }
  local files = vim.tbl_keys(grouped)
  table.sort(files)

  for _, file in ipairs(files) do
    table.insert(out, "")
    table.insert(out, "## " .. file)

    table.sort(grouped[file], function(a, b)
      if a.lnum == b.lnum then
        return a.col < b.col
      end
      return a.lnum < b.lnum
    end)

    for _, item in ipairs(grouped[file]) do
      local severity = vim.diagnostic.severity[item.severity]
      local message = item.message:gsub("\n", " ")
      table.insert(out, string.format("- [%s] Line %d, Col %d: %s", severity, item.lnum + 1, item.col + 1, message))
    end
  end

  return table.concat(out, "\n"), nil
end

local function find_tmux_target()
  local panes = vim.fn.system('tmux list-panes -F "#{pane_id} #{pane_current_command}" 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    return nil, "not in tmux session"
  end

  for line in panes:gmatch("[^\n]+") do
    local pane_id, command = line:match("^(%S+)%s*(.*)$")
    if pane_id and matches_process(command) then
      return pane_id, nil
    end
  end

  return nil, "no pane running " .. process_name_label() .. " in current window"
end

local function copy_to_clipboard(message)
  vim.fn.setreg("+", message)
end

local function send_message_to_tmux(message, opts)
  opts = opts or {}
  local submit = opts.submit == true
  local switch_to_target = opts.switch_to_target
  if switch_to_target == nil then
    switch_to_target = true
  end

  local target, err = find_tmux_target()
  if not target then
    copy_to_clipboard(message)
    vim.notify(err .. ", copied to clipboard", vim.log.levels.WARN)
    return
  end

  local temp_file = vim.fn.tempname()
  local file = io.open(temp_file, "w")
  if not file then
    copy_to_clipboard(message)
    vim.notify("failed to create temp file, copied to clipboard", vim.log.levels.ERROR)
    return
  end
  file:write(message)
  file:close()

  local cmd = string.format(
    "tmux load-buffer %s \\; paste-buffer -p -t %s \\; delete-buffer%s",
    vim.fn.shellescape(temp_file),
    vim.fn.shellescape(target),
    submit and (" \\; send-keys -t " .. vim.fn.shellescape(target) .. " Enter") or ""
  )
  vim.fn.system(cmd)
  vim.fn.delete(temp_file)

  if vim.v.shell_error ~= 0 then
    copy_to_clipboard(message)
    vim.notify("failed to send to " .. target .. ", copied to clipboard", vim.log.levels.WARN)
    return
  end

  if not switch_to_target then
    vim.notify(submit and ("sent and submitted to " .. target) or ("sent message to " .. target))
    return
  end

  vim.fn.system("tmux select-pane -t " .. vim.fn.shellescape(target))
end

local function clear_prompt_state()
  if state.prompt_window then
    pcall(function()
      state.prompt_window:close({ buf = false })
    end)
  end
  if state.prompt_buffer and vim.api.nvim_buf_is_valid(state.prompt_buffer) then
    vim.api.nvim_buf_delete(state.prompt_buffer, { force = true })
  end
  state.prompt_buffer = nil
  state.prompt_window = nil
  state.prompt_callback = nil
  state.prompt_cursor = nil
  state.prompt_insert_mode = false
end

local function content_lines(content)
  if content == nil or content == "" then
    return { "" }
  end

  local lines = vim.split(content, "\n", { plain = true })
  table.insert(lines, "")
  return lines
end

local function append_to_prompt(buf, content)
  if not content or content == "" then
    return
  end

  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local lines = content_lines(content)
  if #current_lines > 0 and current_lines[#current_lines] ~= "" then
    vim.api.nvim_buf_set_lines(buf, #current_lines, #current_lines, false, { "" })
    current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  vim.api.nvim_buf_set_lines(buf, #current_lines, #current_lines, false, lines)
end

local function prompt_cursor_at_end(buf)
  local line = math.max(1, vim.api.nvim_buf_line_count(buf))
  local last = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  return { line, #last }
end

local function save_prompt_view_state(insert_mode)
  if not (state.prompt_window and state.prompt_window.win and vim.api.nvim_win_is_valid(state.prompt_window.win)) then
    return
  end

  state.prompt_cursor = vim.api.nvim_win_get_cursor(state.prompt_window.win)
  if insert_mode == nil then
    local mode = vim.api.nvim_get_mode().mode
    insert_mode = mode:sub(1, 1) == "i"
  end
  state.prompt_insert_mode = insert_mode
end

local function apply_prompt_view_state(buf, cursor, insert_mode)
  if not state.prompt_window then
    return
  end

  vim.schedule(function()
    if not (state.prompt_window and state.prompt_window.win and vim.api.nvim_win_is_valid(state.prompt_window.win)) then
      return
    end

    local max_line = math.max(1, vim.api.nvim_buf_line_count(buf))
    local line = math.min(math.max(1, cursor[1]), max_line)
    local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
    local col = math.min(math.max(0, cursor[2]), #text)

    pcall(vim.api.nvim_win_set_cursor, state.prompt_window.win, { line, col })
    if insert_mode then
      vim.cmd.startinsert()
    end
  end)
end

local function restore_prompt_view_state(buf)
  local cursor = state.prompt_cursor or prompt_cursor_at_end(buf)
  apply_prompt_view_state(buf, cursor, state.prompt_insert_mode)
end

local function send_prompt(opts)
  if not (state.prompt_buffer and vim.api.nvim_buf_is_valid(state.prompt_buffer)) then
    return
  end

  opts = opts or {}
  local lines = vim.api.nvim_buf_get_lines(state.prompt_buffer, 0, -1, false)
  local content = table.concat(lines, "\n")
  local callback = state.prompt_callback or send_message_to_tmux
  clear_prompt_state()
  callback(content, opts)
end

local function cancel_prompt()
  clear_prompt_state()
end

local function hide_prompt(insert_mode)
  if state.prompt_window then
    save_prompt_view_state(insert_mode)
    state.prompt_window:hide()
  end
end

local function setup_prompt_buffer(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "text"
  vim.api.nvim_buf_set_name(buf, "Agent Prompt")
  vim.diagnostic.enable(false, { bufnr = buf })

  local map_opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", cancel_prompt, map_opts)
  vim.keymap.set("n", "<Esc>", cancel_prompt, map_opts)
  vim.keymap.set("n", "<leader>x", hide_prompt, map_opts)
  vim.keymap.set("n", "<M-s>", function()
    send_prompt()
  end, map_opts)
  vim.keymap.set("n", "<C-s>", function()
    send_prompt({ submit = true, switch_to_target = false })
  end, map_opts)
  vim.keymap.set("n", "<C-c>", cancel_prompt, map_opts)
  vim.keymap.set("n", "<C-x>", hide_prompt, map_opts)
  vim.keymap.set("i", "<M-s>", function()
    vim.cmd.stopinsert()
    send_prompt()
  end, map_opts)
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd.stopinsert()
    send_prompt({ submit = true, switch_to_target = false })
  end, map_opts)
  vim.keymap.set("i", "<C-c>", function()
    vim.cmd.stopinsert()
    cancel_prompt()
  end, map_opts)
  vim.keymap.set("i", "<C-x>", function()
    vim.cmd.stopinsert()
    hide_prompt(true)
  end, map_opts)
end

local function ensure_prompt_window(buf)
  local win = state.prompt_window
  if not win then
    win = require("snacks").win.new({
      buf = buf,
      enter = true,
      show = false,
      fixbuf = true,
      minimal = false,
      position = "float",
      relative = "editor",
      width = config.prompt.width_ratio,
      height = config.prompt.height_ratio,
      border = vim.o.winborder ~= "" and vim.o.winborder or "rounded",
      title = config.prompt.title,
      title_pos = "center",
      backdrop = false,
      keys = {
        q = false,
      },
      wo = {
        wrap = true,
        linebreak = true,
        number = false,
        relativenumber = false,
        signcolumn = "no",
      },
    })
    win:add_padding()
    state.prompt_window = win
  end

  win:show()
  win:focus()
  return win
end

local function open_prompt(initial_content, callback)
  local buf = state.prompt_buffer
  local is_reuse = buf and vim.api.nvim_buf_is_valid(buf)

  if not is_reuse then
    buf = vim.api.nvim_create_buf(false, true)
    state.prompt_buffer = buf
    setup_prompt_buffer(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines(initial_content or ""))
  else
    append_to_prompt(buf, initial_content)
  end

  state.prompt_callback = callback
  ensure_prompt_window(buf)
  local cursor = prompt_cursor_at_end(buf)
  state.prompt_cursor = cursor
  state.prompt_insert_mode = true
  apply_prompt_view_state(buf, cursor, true)
end

local function resume_prompt()
  if state.prompt_buffer and vim.api.nvim_buf_is_valid(state.prompt_buffer) then
    state.prompt_callback = state.prompt_callback or send_message_to_tmux
    ensure_prompt_window(state.prompt_buffer)
    restore_prompt_view_state(state.prompt_buffer)
    return
  end

  vim.notify("no prompt to resume", vim.log.levels.WARN)
end

function M.compose_visual()
  local opts = visual_selection_opts()
  opts.interactive_prompt = true
  M.send_file(opts)
end

function M.send_visual()
  M.send_file(visual_selection_opts())
end

local function dispatch(builder, opts)
  local context, err = builder(opts)
  if not context or context == "" then
    vim.notify(err or "no context available", vim.log.levels.WARN)
    return
  end

  if opts and opts.interactive_prompt then
    open_prompt(context, send_message_to_tmux)
  else
    send_message_to_tmux(context)
  end
end

function M.send_file(opts)
  dispatch(build_file_context, opts or {})
end

function M.send_diagnostics(opts)
  dispatch(build_diagnostics_context, opts or {})
end

function M.resume_prompt()
  resume_prompt()
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
end

function M.setup(opts)
  if state.setup_done then
    return M
  end

  config = vim.tbl_deep_extend("force", config, opts or {})
  create_commands()
  state.setup_done = true
  return M
end

return M
