local M = {}

local config = {
  width_ratio = 0.6,
  height_ratio = 0.35,
  title = " Compose to Agent ",
}

local send_message

local state = {
  buffer = nil,
  window = nil,
  cursor = nil,
  insert_mode = false,
}

function M.setup(opts, sender)
  config = vim.tbl_deep_extend("force", config, opts or {})
  send_message = sender
end

function M.buffer()
  return state.buffer
end

local function clear()
  if state.window then
    pcall(function()
      state.window:close({ buf = false })
    end)
  end
  if state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
    vim.api.nvim_buf_delete(state.buffer, { force = true })
  end
  state.buffer = nil
  state.window = nil
  state.cursor = nil
  state.insert_mode = false
end

local function content_lines(content)
  if content == nil or content == "" then
    return { "" }
  end

  local lines = vim.split(content, "\n", { plain = true })
  table.insert(lines, "")
  return lines
end

local function append(buf, content)
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

local function cursor_at_end(buf)
  local line = math.max(1, vim.api.nvim_buf_line_count(buf))
  local last = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  return { line, #last }
end

local function save_view_state(insert_mode)
  if not (state.window and state.window.win and vim.api.nvim_win_is_valid(state.window.win)) then
    return
  end

  state.cursor = vim.api.nvim_win_get_cursor(state.window.win)
  if insert_mode == nil then
    local mode = vim.api.nvim_get_mode().mode
    insert_mode = mode:sub(1, 1) == "i"
  end
  state.insert_mode = insert_mode
end

local function apply_view_state(buf, cursor, insert_mode)
  if not state.window then
    return
  end

  vim.schedule(function()
    if not (state.window and state.window.win and vim.api.nvim_win_is_valid(state.window.win)) then
      return
    end

    local max_line = math.max(1, vim.api.nvim_buf_line_count(buf))
    local line = math.min(math.max(1, cursor[1]), max_line)
    local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
    local col = math.min(math.max(0, cursor[2]), #text)

    pcall(vim.api.nvim_win_set_cursor, state.window.win, { line, col })
    if insert_mode then
      vim.cmd.startinsert()
    end
  end)
end

local function restore_view_state(buf)
  local cursor = state.cursor or cursor_at_end(buf)
  apply_view_state(buf, cursor, state.insert_mode)
end

local function send(opts)
  if not (state.buffer and vim.api.nvim_buf_is_valid(state.buffer)) then
    return
  end

  opts = opts or {}
  local lines = vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false)
  local content = table.concat(lines, "\n")
  send_message(content, opts, function(sent)
    if sent then
      clear()
    end
  end)
end

local function hide(insert_mode)
  if state.window then
    save_view_state(insert_mode)
    state.window:hide()
  end
end

local function setup_buffer(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "text"
  vim.api.nvim_buf_set_name(buf, "Agent Prompt")
  vim.diagnostic.enable(false, { bufnr = buf })

  local map_opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", clear, map_opts)
  vim.keymap.set("n", "<Esc>", clear, map_opts)
  vim.keymap.set("n", "<leader>x", hide, map_opts)
  vim.keymap.set("n", "<M-s>", function()
    send()
  end, map_opts)
  vim.keymap.set("n", "<C-s>", function()
    send({ submit = true, switch_to_target = false })
  end, map_opts)
  vim.keymap.set("n", "<C-c>", clear, map_opts)
  vim.keymap.set("n", "<C-x>", hide, map_opts)
  vim.keymap.set("i", "<M-s>", function()
    vim.cmd.stopinsert()
    send()
  end, map_opts)
  vim.keymap.set("i", "<C-s>", function()
    vim.cmd.stopinsert()
    send({ submit = true, switch_to_target = false })
  end, map_opts)
  vim.keymap.set("i", "<C-c>", function()
    vim.cmd.stopinsert()
    clear()
  end, map_opts)
  vim.keymap.set("i", "<C-x>", function()
    vim.cmd.stopinsert()
    hide(true)
  end, map_opts)
end

local function ensure_window(buf)
  local win = state.window
  if not win then
    win = require("snacks").win.new({
      buf = buf,
      enter = true,
      show = false,
      fixbuf = true,
      minimal = false,
      position = "float",
      relative = "editor",
      width = config.width_ratio,
      height = config.height_ratio,
      border = vim.o.winborder ~= "" and vim.o.winborder or "rounded",
      title = config.title,
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
    state.window = win
  end

  win:show()
  win:focus()
end

function M.open(initial_content)
  local buf = state.buffer
  local is_reuse = buf and vim.api.nvim_buf_is_valid(buf)

  if not is_reuse then
    buf = vim.api.nvim_create_buf(false, true)
    state.buffer = buf
    setup_buffer(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines(initial_content or ""))
  else
    append(buf, initial_content)
  end

  ensure_window(buf)
  local cursor = cursor_at_end(buf)
  state.cursor = cursor
  state.insert_mode = true
  apply_view_state(buf, cursor, true)
end

function M.resume()
  if state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
    ensure_window(state.buffer)
    restore_view_state(state.buffer)
    return
  end

  vim.notify("no prompt to resume", vim.log.levels.WARN)
end

return M
