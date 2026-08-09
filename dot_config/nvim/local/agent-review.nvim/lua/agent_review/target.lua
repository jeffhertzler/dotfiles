local M = {}

local function notify(message)
  vim.notify(message, vim.log.levels.WARN, { title = "Agent Review" })
end

local function normalize_path(path, root)
  if not path or path == "" then
    return nil
  end

  path = vim.fs.normalize(path)
  root = root and vim.fs.normalize(root) or nil
  if root and vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  return path
end

local function repository_context(path)
  local root = vim.fs.root(path, { ".jj", ".git" })
  if not root then
    return nil, "files"
  end
  root = vim.fs.normalize(root)
  local backend = vim.uv.fs_stat(root .. "/.jj") and "jj" or "git"
  return root, backend
end

local function agent_diff_context(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end
  local metadata = vim.b[bufnr].agent_diff_context
  if type(metadata) ~= "table" or not metadata.path then
    return nil
  end
  return {
    bufnr = bufnr,
    tabpage = vim.api.nvim_get_current_tabpage(),
    host = "agent_diff",
    view_side = metadata.side,
    root = metadata.root,
    backend = "git",
    path = metadata.path,
    side = metadata.side,
    selected_revision = metadata.selected_revision,
    base_revision = metadata.base_revision,
    target_revision = metadata.target_revision,
  }
end

local function codediff_path(path)
  if type(path) ~= "table" then
    return path
  end
  if path.absolute and path.absolute ~= "" then
    return path.absolute
  end
  return path.relative
end

local function codediff_context(bufnr)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return nil
  end

  local tabpage = lifecycle.find_tabpage_by_buffer(bufnr)
  local session = tabpage and lifecycle.get_session(tabpage) or nil
  if not session then
    return nil
  end

  local original_buf, modified_buf = lifecycle.get_buffers(tabpage)
  local original_path, modified_path = lifecycle.get_paths(tabpage)
  original_path = codediff_path(original_path)
  modified_path = codediff_path(modified_path)
  local view_side, path, selected_revision
  if bufnr == original_buf then
    view_side = "old"
    path = original_path
    selected_revision = session.original_revision
  elseif bufnr == modified_buf then
    view_side = "new"
    path = modified_path
    selected_revision = session.modified_revision
  else
    return nil
  end

  local buffer_name = vim.api.nvim_buf_get_name(bufnr)
  local is_virtual = buffer_name:match("^codediff://") ~= nil
  local is_working = not is_virtual and (selected_revision == nil or selected_revision == "WORKING")
  local root = session.git_root and vim.fs.normalize(session.git_root) or nil
  return {
    bufnr = bufnr,
    tabpage = tabpage,
    host = "codediff",
    view_side = view_side,
    root = root,
    backend = root and "git" or "files",
    path = normalize_path(path, root),
    side = is_working and "working" or view_side,
    selected_revision = selected_revision or "WORKING",
    base_revision = session.original_revision,
    target_revision = session.modified_revision,
  }
end

local function buffer_context(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end
  if vim.bo[bufnr].buftype ~= "" then
    return nil
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or name:match("^%w+://") then
    return nil
  end
  local absolute_path = vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
  local root, backend = repository_context(absolute_path)
  return {
    bufnr = bufnr,
    tabpage = vim.api.nvim_get_current_tabpage(),
    host = "buffer",
    view_side = nil,
    root = root,
    backend = backend,
    path = normalize_path(absolute_path, root),
    side = "working",
    selected_revision = "WORKING",
    base_revision = nil,
    target_revision = "WORKING",
  }
end

function M.context_for_buffer(bufnr)
  return agent_diff_context(bufnr) or codediff_context(bufnr) or buffer_context(bufnr)
end

local function ordered_positions(first, last)
  if first[1] > last[1] or (first[1] == last[1] and first[2] > last[2]) then
    return last, first
  end
  return first, last
end

local function inclusive_end_col(bufnr, line, column)
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local byte_index = math.max(0, math.min(column - 1, #text))
  local character = vim.fn.matchstr(text:sub(byte_index + 1), "^.")
  return byte_index + #character
end

function M.end_col_exclusive(bufnr, target)
  if not target.end_col then
    local text = vim.api.nvim_buf_get_lines(bufnr, target.end_line - 1, target.end_line, false)[1] or ""
    return #text
  end
  return inclusive_end_col(bufnr, target.end_line, target.end_col)
end

function M.previous_char_col(bufnr, line, exclusive_col)
  if exclusive_col <= 0 then
    return 1
  end
  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  local prefix = text:sub(1, exclusive_col)
  local character = vim.fn.matchstr(prefix, ".$")
  return math.max(1, exclusive_col - #character + 1)
end

local function selected_lines(bufnr, target)
  local lines = vim.api.nvim_buf_get_lines(bufnr, target.start_line - 1, target.end_line, false)
  if #lines == 0 then
    return {}
  end

  if target.start_col then
    local start_byte = target.start_col - 1
    local end_byte = M.end_col_exclusive(bufnr, target)
    if #lines == 1 then
      lines[1] = lines[1]:sub(start_byte + 1, end_byte)
    else
      lines[1] = lines[1]:sub(start_byte + 1)
      lines[#lines] = lines[#lines]:sub(1, end_byte)
    end
  end
  return lines
end

local function surrounding_context(bufnr, target)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local before_start = math.max(0, target.start_line - 4)
  local after_end = math.min(line_count, target.end_line + 3)
  return {
    before = vim.api.nvim_buf_get_lines(bufnr, before_start, target.start_line - 1, false),
    selected = selected_lines(bufnr, target),
    after = vim.api.nvim_buf_get_lines(bufnr, target.end_line, after_end, false),
  }
end

function M.anchor_for_buffer(bufnr, target)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return nil
  end
  return surrounding_context(bufnr, target)
end

function M.current_context()
  local context = M.context_for_buffer(vim.api.nvim_get_current_buf())
  if context and context.path then
    return context
  end

  local best, latest = nil, -1
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      local bufnr = vim.api.nvim_win_get_buf(winid)
      local candidate = M.context_for_buffer(bufnr)
      if candidate and candidate.path then
        local info = vim.fn.getbufinfo(bufnr)[1]
        local lastused = info and info.lastused or 0
        if lastused > latest then
          best, latest = candidate, lastused
        end
      end
    end
  end
  return best
end

function M.capture(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.b[bufnr].agent_diff_patch then
    return require("agent_review.patch").capture(opts)
  end
  local context = M.context_for_buffer(bufnr)
  if not context or not context.path then
    notify("Annotations require a regular file or a supported diff buffer")
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local target = {
    file = context.path,
    side = context.side,
    start_line = cursor_line,
    end_line = cursor_line,
    selection = "line",
    column_encoding = "utf-8-byte",
  }

  if opts.visual then
    local mode = vim.fn.mode(1):sub(1, 1)
    if mode == "\22" then
      notify("Blockwise annotation is not implemented yet")
      return nil
    end

    local first = vim.fn.getpos("v")
    local last = vim.fn.getpos(".")
    first, last = ordered_positions({ first[2], first[3] }, { last[2], last[3] })
    target.start_line = first[1]
    target.end_line = last[1]

    if mode == "v" then
      target.selection = "character"
      target.start_col = first[2]
      target.end_col = last[2]
    end
  end

  return {
    tabpage = context.tabpage,
    bufnr = bufnr,
    host = context.host,
    root = context.root,
    revision = {
      backend = context.backend,
      base_expression = context.base_revision,
      target_expression = context.target_revision,
      selected_expression = context.selected_revision,
    },
    target = target,
    anchor = surrounding_context(bufnr, target),
  }
end

return M
