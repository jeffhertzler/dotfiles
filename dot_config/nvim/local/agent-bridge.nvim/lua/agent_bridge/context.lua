local M = {}

local prompt_buffer = function()
  return nil
end

function M.setup(opts)
  prompt_buffer = opts and opts.prompt_buffer or prompt_buffer
end

local function is_real_file_buffer(buf)
  return buf ~= prompt_buffer() and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function relative_buf_name(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return ""
  end
  return vim.fn.fnamemodify(path, ":~:.")
end

local function target_buf()
  local current = vim.api.nvim_get_current_buf()
  if is_real_file_buffer(current) then
    return current
  end

  local best_buf = nil
  local latest_lastused = -1
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_real_file_buffer(buf) then
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
  return relative_buf_name(buf or target_buf())
end

function M.visual_selection_opts()
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

function M.build_file(opts)
  opts = opts or {}

  if opts.use_all_buffers then
    local buffers = {}
    local current = current_file()

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and is_real_file_buffer(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        local relative = relative_buf_name(buf)
        if vim.fn.filereadable(name) == 1 and not relative:match("^term://") and not relative:match("^%[") then
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

function M.build_diagnostics(opts)
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
    local relative = relative_buf_name(item.bufnr)
    if relative ~= "" and is_real_file_buffer(item.bufnr) then
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

return M
