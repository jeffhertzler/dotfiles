local M = {}

local next_id = 0

local Input = {}
Input.__index = Input

local function content_lines(content)
  if content == nil or content == "" then
    return { "" }
  end
  return vim.split(content, "\n", { plain = true })
end

local function cursor_at_end(buf)
  local line = math.max(1, vim.api.nvim_buf_line_count(buf))
  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  return { line, #text }
end

function Input:_valid_buffer()
  return self.buffer and vim.api.nvim_buf_is_valid(self.buffer)
end

function Input:_valid_window()
  return self.window and self.window.win and vim.api.nvim_win_is_valid(self.window.win)
end

function Input:_capture_origin()
  local win = vim.api.nvim_get_current_win()
  if self:_valid_window() and win == self.window.win then
    return
  end
  self.origin_generation = (self.origin_generation or 0) + 1
  self.origin_win = win
  self.origin_insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

function Input:_restore_origin()
  local generation = self.origin_generation
  local win = self.origin_win
  local insert_mode = self.origin_insert_mode == true
  self.origin_win = nil
  self.origin_insert_mode = nil

  pcall(vim.cmd, "stopinsert")
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_set_current_win, win)
  end
  vim.schedule(function()
    if self.origin_generation ~= generation then
      return
    end
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_set_current_win, win)
      pcall(vim.cmd, insert_mode and "startinsert" or "stopinsert")
    elseif not insert_mode then
      pcall(vim.cmd, "stopinsert")
    end
  end)
end

function Input:_resize()
  if not self:_valid_buffer() or not self:_valid_window() then
    return
  end
  local lines = vim.api.nvim_buf_line_count(self.buffer)
  self.window.opts.height = math.max(self.opts.min_height, math.min(self.opts.max_height, lines))
  self.window.opts.wo.cursorline = self.opts.cursorline and lines > 1
  self.window:update()
end

function Input:_save_view(insert_mode)
  if not self:_valid_window() then
    return
  end
  self.cursor = vim.api.nvim_win_get_cursor(self.window.win)
  if insert_mode == nil then
    insert_mode = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  end
  self.insert_mode = insert_mode
end

function Input:_restore_view()
  if not self:_valid_window() then
    return
  end
  local cursor = self.cursor or cursor_at_end(self.buffer)
  local max_line = math.max(1, vim.api.nvim_buf_line_count(self.buffer))
  local line = math.max(1, math.min(cursor[1], max_line))
  local text = vim.api.nvim_buf_get_lines(self.buffer, line - 1, line, false)[1] or ""
  local col = math.max(0, math.min(cursor[2], #text))
  vim.schedule(function()
    if not self:_valid_window() then
      return
    end
    vim.api.nvim_win_set_cursor(self.window.win, { line, col })
    if self.insert_mode ~= false then
      vim.cmd("startinsert!")
    end
  end)
end

function Input:value()
  if not self:_valid_buffer() then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(self.buffer, 0, -1, false), "\n")
end

function Input:close()
  pcall(vim.cmd, "stopinsert")
  if self.window then
    pcall(function()
      self.window:close({ buf = false })
    end)
  end
  if self:_valid_buffer() then
    pcall(vim.api.nvim_buf_delete, self.buffer, { force = true })
  end
  self.buffer = nil
  self.window = nil
  self.cursor = nil
  self.insert_mode = true
  self:_restore_origin()
end

function Input:hide(insert_mode)
  if not self.opts.persistent then
    self:close()
    return
  end
  if self:_valid_window() then
    self:_save_view(insert_mode)
    self.window:hide()
    self:_restore_origin()
  end
end

function Input:_accept(action)
  if self.accepting or not self:_valid_buffer() then
    return
  end
  local value = self:value()
  if vim.trim(value) == "" then
    vim.notify("input cannot be empty", vim.log.levels.WARN)
    return
  end
  self.accepting = true
  local finished = false
  local function done(ok)
    if finished then
      return
    end
    finished = true
    self.accepting = false
    if ok then
      self:close()
    end
  end
  local result = self.opts.on_accept(value, action or {}, done)
  if result ~= nil and not finished then
    done(result ~= false)
  end
end

function Input:_map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, {
    buffer = self.buffer,
    silent = true,
    nowait = true,
    desc = desc,
  })
end

function Input:_setup_buffer()
  local buf = self.buffer
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = self.opts.filetype
  vim.api.nvim_buf_set_name(buf, string.format("Agent Input %d", self.id))
  vim.diagnostic.enable(false, { bufnr = buf })

  self:_map("n", "q", function() self:close() end, "Cancel")
  self:_map("n", "<Esc>", function() self:close() end, "Cancel")
  self:_map("n", "<C-c>", function() self:close() end, "Cancel")
  self:_map("i", "<C-c>", function() self:close() end, "Cancel")
  self:_map("n", "<CR>", function() self:_accept({ action = "default" }) end, self.opts.accept_label)
  self:_map({ "n", "i" }, "<C-s>", function()
    self:_accept(self.opts.ctrl_s or { action = "default" })
  end, self.opts.ctrl_s_label or self.opts.accept_label)

  if self.opts.meta_s ~= false then
    self:_map({ "n", "i" }, "<M-s>", function()
      self:_accept(self.opts.meta_s or { action = "default" })
    end, self.opts.meta_s_label or self.opts.accept_label)
  end

  self:_map("n", "<C-x>", function() self:hide(false) end, self.opts.persistent and "Hide" or "Cancel")
  self:_map("i", "<C-x>", function()
    vim.cmd.stopinsert()
    self:hide(true)
  end, self.opts.persistent and "Hide" or "Cancel")

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = self.group,
    buffer = buf,
    callback = function() self:_resize() end,
  })
end

function Input:_ensure_window()
  if self:_valid_window() then
    self.window:show()
    self.window:focus()
    self:_resize()
    return
  end

  local requested_width = self.opts.width
  if type(requested_width) == "number" and requested_width > 0 and requested_width < 1 then
    requested_width = math.floor(vim.o.columns * requested_width)
  end
  requested_width = math.max(requested_width or 1, self.opts.min_width or 1)
  requested_width = math.min(requested_width, math.max(20, vim.o.columns - 6))

  local win = require("snacks").win.new({
    buf = self.buffer,
    enter = true,
    show = false,
    fixbuf = true,
    minimal = false,
    position = "float",
    relative = "editor",
    width = requested_width,
    height = self.opts.min_height,
    border = vim.o.winborder ~= "" and vim.o.winborder or "rounded",
    title = self.opts.title,
    title_pos = "center",
    footer = self.opts.footer,
    footer_pos = "center",
    backdrop = false,
    keys = { q = false },
    wo = {
      wrap = true,
      linebreak = true,
      cursorline = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      statuscolumn = " ",
      winhighlight = table.concat({
        "Normal:SnacksInputNormal",
        "NormalFloat:SnacksInputNormal",
        "FloatBorder:SnacksInputBorder",
        "FloatTitle:SnacksInputTitle",
        "FloatFooter:SnacksInputTitle",
      }, ","),
    },
  })
  win:add_padding()
  self.window = win
  win:show()
  win:focus()
  self:_resize()
end

function Input:open(initial, opts)
  opts = opts or {}
  self:_capture_origin()
  local reused = self:_valid_buffer()
  if not reused then
    self.buffer = vim.api.nvim_create_buf(false, true)
    self:_setup_buffer()
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, content_lines(initial))
  elseif opts.append and initial and initial ~= "" then
    local lines = content_lines(initial)
    local count = vim.api.nvim_buf_line_count(self.buffer)
    local last = vim.api.nvim_buf_get_lines(self.buffer, count - 1, count, false)[1] or ""
    if last ~= "" then
      vim.api.nvim_buf_set_lines(self.buffer, count, count, false, { "" })
      count = count + 1
    end
    vim.api.nvim_buf_set_lines(self.buffer, count, count, false, lines)
  elseif initial ~= nil then
    vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, content_lines(initial))
  end

  self:_ensure_window()
  self.cursor = cursor_at_end(self.buffer)
  self.insert_mode = true
  self:_restore_view()
  return self
end

function Input:resume()
  if not self:_valid_buffer() then
    return false
  end
  self:_capture_origin()
  self:_ensure_window()
  self:_restore_view()
  return true
end

function M.new(opts)
  opts = vim.tbl_deep_extend("force", {
    title = " Input ",
    width = 0.5,
    min_width = 48,
    min_height = 1,
    max_height = 8,
    filetype = "markdown",
    persistent = false,
    cursorline = true,
    accept_label = "Accept",
    on_accept = function(_, _, done) done(true) end,
  }, opts or {})
  next_id = next_id + 1
  local instance = setmetatable({
    id = next_id,
    opts = opts,
    group = vim.api.nvim_create_augroup("AgentInput" .. next_id, { clear = true }),
    insert_mode = true,
    accepting = false,
  }, Input)
  return instance
end

return M
