local M = {}

local active
local setup_buffer
local ns = vim.api.nvim_create_namespace("agent_diff_patch")

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Agent Patch" })
end

local function split_lines(text)
  if not text or text == "" then
    return {}
  end
  return vim.split(text:gsub("\n$", ""), "\n", { plain = true })
end

local function git_output_async(root, args, callback)
  local command = { "git", "-C", root }
  vim.list_extend(command, args)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, vim.trim(result.stderr or "git command failed"))
      else
        callback(result.stdout or "")
      end
    end)
  end)
end

local function parse_range(value)
  local old_start, old_count, new_start, new_count = value:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return nil
  end
  return tonumber(old_start), tonumber(old_count ~= "" and old_count or "1"), tonumber(new_start), tonumber(new_count ~= "" and new_count or "1")
end

local function parse_patch(text, section)
  local headers, hunks, current = {}, {}, nil
  for _, line in ipairs(split_lines(text)) do
    local old_start, old_count, new_start, new_count = parse_range(line)
    if old_start then
      current = {
        section = section,
        header = line,
        old_start = old_start,
        old_count = old_count,
        new_start = new_start,
        new_count = new_count,
        lines = {},
      }
      table.insert(hunks, current)
    elseif current then
      table.insert(current.lines, line)
    else
      table.insert(headers, line)
    end
  end
  return { section = section, headers = headers, hunks = hunks }
end

local function source_context(workspace)
  local session = require("agent_diff").get_session()
  if session and session.root and session.files then
    local file = session.files[session.index]
    if file then
      return session.root, file.path, session.modified_revision == "WORKING" and session.modified_buf or nil
    end
  elseif session and session.root and session.path then
    return session.root, session.path, session.modified_buf
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local context, err = require("agent_diff.git").context(bufnr)
  if not context then
    return nil, err
  end
  return context.root, context.relative_path, bufnr
end

local function load_sections(workspace, callback)
  local common = { "diff", "--no-ext-diff", "--no-color", "--unified=3" }
  local staged_args = vim.deepcopy(common)
  table.insert(staged_args, "--cached")
  vim.list_extend(staged_args, { "--", workspace.path })
  local unstaged_args = vim.deepcopy(common)
  vim.list_extend(unstaged_args, { "--", workspace.path })

  local results, remaining, finished = {}, 2, false
  local function complete(name, text, err)
    if finished then
      return
    end
    if err then
      finished = true
      callback(nil, err)
      return
    end
    results[name] = text
    remaining = remaining - 1
    if remaining == 0 then
      finished = true
      callback({
        parse_patch(results.unstaged, "unstaged"),
        parse_patch(results.staged, "staged"),
      })
    end
  end
  git_output_async(workspace.root, staged_args, function(text, err) complete("staged", text, err) end)
  git_output_async(workspace.root, unstaged_args, function(text, err) complete("unstaged", text, err) end)
end

local function add_entry(entries, text, metadata)
  table.insert(entries, { text = text, metadata = metadata })
end

local function render_hunk(entries, section, hunk, hunk_index)
  add_entry(entries, hunk.header, { section = section.section, hunk = hunk, hunk_index = hunk_index, kind = "hunk" })
  local old_line, new_line = hunk.old_start, hunk.new_start
  for index, text in ipairs(hunk.lines) do
    local prefix = text:sub(1, 1)
    local metadata = {
      section = section.section,
      hunk = hunk,
      hunk_index = hunk_index,
      line_index = index,
      kind = prefix == "-" and "delete" or prefix == "+" and "add" or prefix == " " and "context" or "meta",
      text = text:sub(2),
    }
    if prefix == " " then
      metadata.old_line, metadata.new_line = old_line, new_line
      old_line, new_line = old_line + 1, new_line + 1
    elseif prefix == "-" then
      metadata.old_line = old_line
      old_line = old_line + 1
    elseif prefix == "+" then
      metadata.new_line = new_line
      new_line = new_line + 1
    end
    add_entry(entries, text, metadata)
  end
end

local function section_entries(section)
  local entries = {}
  for hunk_index, hunk in ipairs(section.hunks) do
    render_hunk(entries, section, hunk, hunk_index)
    if hunk_index < #section.hunks then
      add_entry(entries, "", { section = section.section, kind = "separator" })
    end
  end
  return entries
end

local function add_row(pane, text, metadata, highlight)
  table.insert(pane.lines, text)
  pane.rows[#pane.lines] = metadata
  if highlight then
    table.insert(pane.highlights, {
      row = #pane.lines - 1,
      end_col = #text,
      group = highlight,
    })
  end
end

local function pane_config(index, count, title, mode)
  local width = math.max(36, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.92)))
  local height
  local row
  if count == 2 then
    height = math.max(6, math.min(14, math.floor((vim.o.lines - 9) / 2)))
    local total = 2 * (height + 2) + 1
    local top = math.max(0, vim.o.lines - total - 2)
    row = top + (index - 1) * (height + 3)
  else
    height = math.max(8, math.min(vim.o.lines - 6, math.floor(vim.o.lines * 0.35)))
    row = math.max(0, vim.o.lines - height - 4)
  end
  return {
    relative = "editor",
    row = row,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title and (" " .. title .. " ") or "",
    title_pos = "center",
    footer = mode and (" " .. (mode == "hunk" and "Hunk mode" or "Line mode") .. " ") or "",
    footer_pos = "right",
    zindex = 100,
  }
end

local function configure_window(win)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].foldenable = false
  vim.wo[win].winhighlight = table.concat({
    "Normal:SnacksInputNormal",
    "NormalFloat:SnacksInputNormal",
    "FloatBorder:SnacksInputBorder",
    "FloatTitle:SnacksInputTitle",
  }, ",")
end

local function close_pane(pane)
  if valid_win(pane.win) then
    pcall(vim.api.nvim_win_close, pane.win, true)
  end
  if valid_buf(pane.buf) then
    pcall(vim.api.nvim_buf_delete, pane.buf, { force = true })
  end
end

local function ensure_pane(workspace, key, index, count, title)
  local pane = workspace.panes[key]
  if not pane or not valid_buf(pane.buf) then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "agentpatch"
    pcall(vim.api.nvim_buf_set_name, buf, "agent-patch://" .. key .. "/" .. workspace.path)
    vim.b[buf].agent_diff_patch = true
    pane = { key = key, buf = buf, rows = {}, lines = {}, highlights = {} }
    workspace.panes[key] = pane
    setup_buffer(workspace, pane)
  end
  local config = pane_config(index, count, title, key ~= "loading" and key ~= "empty" and workspace.mode or nil)
  if valid_win(pane.win) then
    vim.api.nvim_win_set_config(pane.win, config)
  else
    pane.win = vim.api.nvim_open_win(pane.buf, false, config)
    configure_window(pane.win)
  end
  return pane
end

local function syntax_highlight(workspace, pane)
  local ok, highlight = pcall(require, "snacks.picker.util.highlight")
  local ft = vim.filetype.match({ filename = workspace.path })
  if not ok or not ft or ft == "" then
    return
  end
  for _, side in ipairs({ "old", "new" }) do
    local lines, rows = {}, {}
    for row, metadata in ipairs(pane.rows) do
      local include = metadata.kind == "context"
        or side == "old" and metadata.kind == "delete"
        or side == "new" and metadata.kind == "add"
      if include and #lines < 400 then
        table.insert(lines, metadata.text)
        rows[#lines] = row - 1
      end
    end
    if #lines > 0 then
      local chunks = highlight.get_virtual_lines(table.concat(lines, "\n"), { ft = ft })
      for line, parts in ipairs(chunks) do
        local col = 1
        for _, part in ipairs(parts) do
          local text, group = part[1], part[2]
          if type(group) == "string" and text ~= "" and rows[line] then
            pcall(vim.api.nvim_buf_set_extmark, pane.buf, ns, rows[line], col, {
              end_col = col + #text,
              hl_group = group,
              priority = 260,
            })
          end
          col = col + #text
        end
      end
    end
  end
end

local function refine_changes(pane)
  local ok_diff, diff = pcall(require, "codediff.core.diff")
  local ok_ranges, ranges = pcall(require, "agent_diff.ranges")
  if not ok_diff or not ok_ranges then
    return
  end
  local block
  local deadline = vim.uv.hrtime() + 24 * 1e6
  local function flush()
    if not block or #block.old == 0 or #block.new == 0 then
      block = nil
      return
    end
    local remaining_ms = math.floor((deadline - vim.uv.hrtime()) / 1e6)
    if remaining_ms <= 0 then
      block = nil
      return
    end
    local ok, result = pcall(diff.compute_diff, block.old, block.new, { timeout_ms = math.min(12, remaining_ms) })
    if ok and result then
      ranges.apply(pane.buf, ns, result, block.old, block.new, block.old_rows, block.new_rows, {
        column_offset = 1,
        priority = 280,
      })
    end
    block = nil
  end
  for row, metadata in ipairs(pane.rows) do
    if metadata.kind == "delete" or metadata.kind == "add" then
      if block and block.hunk ~= metadata.hunk then
        flush()
      end
      block = block or { hunk = metadata.hunk, old = {}, new = {}, old_rows = {}, new_rows = {} }
      if metadata.kind == "delete" then
        table.insert(block.old, metadata.text)
        block.old_rows[#block.old] = row - 1
      else
        table.insert(block.new, metadata.text)
        block.new_rows[#block.new] = row - 1
      end
    else
      flush()
    end
  end
  flush()
end

local function render_pane(workspace, pane, section)
  pane.lines, pane.rows, pane.highlights = {}, {}, {}
  vim.api.nvim_buf_clear_namespace(pane.buf, ns, 0, -1)
  if section then
    for _, entry in ipairs(section_entries(section)) do
      entry.metadata.source_col_offset = 1
      local group = entry.metadata.kind == "delete" and "CodeDiffLineDelete"
        or entry.metadata.kind == "add" and "CodeDiffLineInsert"
        or entry.metadata.kind == "hunk" and "DiffText"
        or nil
      add_row(pane, entry.text, entry.metadata, group)
    end
  else
    add_row(pane, "No staged or unstaged changes", { kind = "empty" }, "Comment")
  end
  vim.bo[pane.buf].modifiable = true
  vim.api.nvim_buf_set_lines(pane.buf, 0, -1, false, pane.lines)
  vim.bo[pane.buf].modifiable = false
  for _, item in ipairs(pane.highlights) do
    vim.api.nvim_buf_set_extmark(pane.buf, ns, item.row, 0, {
      end_col = item.end_col,
      hl_group = item.group,
      hl_eol = item.group == "CodeDiffLineDelete" or item.group == "CodeDiffLineInsert",
      priority = 200,
    })
  end
end

local function current_pane(workspace)
  local buf = vim.api.nvim_get_current_buf()
  for _, pane in pairs(workspace.panes or {}) do
    if pane.buf == buf and valid_win(pane.win) then
      return pane
    end
  end
  return workspace.panes and (workspace.panes.unstaged or workspace.panes.staged or workspace.panes.empty)
end

local function render(workspace, cursors)
  local previous = current_pane(workspace)
  local previous_key = previous and previous.key or nil
  local visible = {}
  for _, section in ipairs(workspace.sections) do
    if #section.hunks > 0 then
      table.insert(visible, section)
    end
  end
  local desired = {}
  if #visible == 0 then
    desired.empty = true
  else
    for _, section in ipairs(visible) do
      desired[section.section] = true
    end
  end
  for key, pane in pairs(workspace.panes) do
    if not desired[key] then
      close_pane(pane)
      workspace.panes[key] = nil
    end
  end

  local focus
  if #visible == 0 then
    local pane = ensure_pane(workspace, "empty", 1, 1, nil)
    render_pane(workspace, pane, nil)
    focus = pane
  else
    for index, section in ipairs(visible) do
      local title = section.section == "staged" and "Staged" or "Unstaged"
      local pane = ensure_pane(workspace, section.section, index, #visible, title)
      render_pane(workspace, pane, section)
      local line = cursors and cursors[section.section] or 1
      vim.api.nvim_win_set_cursor(pane.win, { math.max(1, math.min(line, #pane.lines)), 0 })
    end
    focus = previous_key and workspace.panes[previous_key] or workspace.panes[visible[1].section]
  end
  if focus and valid_win(focus.win) then
    vim.api.nvim_set_current_win(focus.win)
  end
  local ok, review_patch = pcall(require, "agent_review.patch")
  if ok then
    review_patch.render(workspace)
  end
  local delay = 8
  for _, section in ipairs(visible) do
    local pane = workspace.panes[section.section]
    if pane then
      pane.decorate_id = (pane.decorate_id or 0) + 1
      local decorate_id = pane.decorate_id
      vim.defer_fn(function()
        if active == workspace and valid_buf(pane.buf) and pane.decorate_id == decorate_id then
          syntax_highlight(workspace, pane)
          refine_changes(pane)
        end
      end, delay)
      delay = delay + 8
    end
  end
end

local function current_location(workspace)
  local pane = current_pane(workspace)
  if not pane or not valid_win(pane.win) then
    return 1, pane
  end
  return vim.api.nvim_win_get_cursor(pane.win)[1], pane
end

function M.refresh()
  local workspace = active
  if not workspace then
    return false
  end
  local cursors = {}
  for key, pane in pairs(workspace.panes or {}) do
    if valid_win(pane.win) then
      cursors[key] = vim.api.nvim_win_get_cursor(pane.win)[1]
    end
  end
  workspace.refresh_id = (workspace.refresh_id or 0) + 1
  local refresh_id = workspace.refresh_id
  load_sections(workspace, function(sections, err)
    if active ~= workspace or refresh_id ~= workspace.refresh_id then
      return
    end
    if not sections then
      notify(err, vim.log.levels.ERROR)
      return
    end
    workspace.sections = sections
    workspace.completed_refresh_id = refresh_id
    render(workspace, cursors)
  end)
  return true
end

local function selected_rows(workspace, opts)
  opts = opts or {}
  local _, pane = current_location(workspace)
  if not pane then
    return nil, "No patch section is focused"
  end
  if not opts.visual and not opts.from_row then
    local row = vim.api.nvim_win_get_cursor(pane.win)[1]
    local metadata = pane.rows[row]
    if not metadata or not metadata.hunk then
      return nil, "Place the cursor on a changed patch line"
    end
    if opts.whole_hunk then
      return metadata, 1, #metadata.hunk.lines
    end
    if metadata.line_index and (metadata.kind == "add" or metadata.kind == "delete") then
      return metadata, metadata.line_index, metadata.line_index
    end
    return nil, "Space toggles one changed line; press a for the whole hunk"
  end
  local first = opts.from_row or vim.fn.getpos("v")[2]
  local last = opts.to_row or vim.fn.getpos(".")[2]
  if first > last then
    first, last = last, first
  end
  local base, from, to
  for row = first, last do
    local metadata = pane.rows[row]
    if metadata and metadata.line_index then
      if not base then
        base, from, to = metadata, metadata.line_index, metadata.line_index
      elseif metadata.hunk ~= base.hunk or metadata.section ~= base.section then
        return nil, "Selection must stay within one hunk"
      else
        from, to = math.min(from, metadata.line_index), math.max(to, metadata.line_index)
      end
    end
  end
  if not base then
    return nil, "Selection contains no patch lines"
  end
  return base, from, to
end

local function generate_patch(workspace, metadata, from, to, reverse)
  local hunk = metadata.hunk
  local content, start_count, offset, selected = {}, hunk.old_count, 0, 0
  for index, line in ipairs(hunk.lines) do
    local prefix, text = line:sub(1, 1), line:sub(2)
    if prefix == "+" or prefix == "-" then
      if index >= from and index <= to then
        offset = offset + (prefix == "+" and 1 or -1)
        selected = selected + 1
        table.insert(content, line)
      elseif not reverse and prefix == "-" then
        table.insert(content, " " .. text)
      elseif reverse then
        if prefix == "+" then
          table.insert(content, " " .. text)
        end
        start_count = start_count + (prefix == "-" and -1 or 1)
      end
    else
      table.insert(content, line)
    end
  end
  if selected == 0 then
    return nil, "Selection contains no changed lines"
  end
  table.insert(content, 1, string.format(
    "@@ -%d,%d +%d,%d @@",
    hunk.old_start,
    start_count,
    hunk.old_start,
    start_count + offset
  ))
  table.insert(content, 1, "+++ b/" .. workspace.path)
  table.insert(content, 1, "--- a/" .. workspace.path)
  return table.concat(content, "\n") .. "\n"
end

local function apply_patch(workspace, patch, opts, callback)
  local args = { "apply", "--whitespace=nowarn" }
  if opts.cached then
    table.insert(args, "--cached")
  end
  if opts.reverse then
    table.insert(args, "--reverse")
  end
  table.insert(args, "-")
  local command = { "git", "-C", workspace.root }
  vim.list_extend(command, args)
  vim.system(command, { text = true, stdin = patch }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, vim.trim(result.stderr or "git apply failed"))
      else
        callback(true)
      end
    end)
  end)
end

local function refresh_source(workspace, changed_worktree)
  if changed_worktree and valid_buf(workspace.source_buf) then
    if vim.bo[workspace.source_buf].modified then
      notify("Working buffer has unsaved changes; reload it manually", vim.log.levels.WARN)
    else
      vim.api.nvim_buf_call(workspace.source_buf, function()
        pcall(vim.cmd, "silent! checktime")
      end)
    end
  end
end

local function show_pending_pane(workspace, key)
  if (key ~= "staged" and key ~= "unstaged") or workspace.panes[key] then
    return
  end
  local other_key = key == "staged" and "unstaged" or "staged"
  if not workspace.panes[other_key] then
    return
  end
  local unstaged = ensure_pane(workspace, "unstaged", 1, 2, "Unstaged")
  local staged = ensure_pane(workspace, "staged", 2, 2, "Staged")
  local pane = key == "staged" and staged or unstaged
  pane.lines = { "Updating…" }
  pane.rows = { { section = key, kind = "loading" } }
  pane.highlights = {}
  vim.api.nvim_buf_clear_namespace(pane.buf, ns, 0, -1)
  vim.bo[pane.buf].modifiable = true
  vim.api.nvim_buf_set_lines(pane.buf, 0, -1, false, pane.lines)
  vim.bo[pane.buf].modifiable = false
end

function M.action(kind, opts)
  opts = opts or {}
  local workspace = active
  if not workspace then
    return false
  end
  if workspace.applying then
    notify("A patch operation is already in progress", vim.log.levels.WARN)
    return false
  end
  local selection_opts = vim.deepcopy(opts)
  if not opts.visual and not opts.from_row then
    if kind == "delete" or kind == "toggle" and workspace.mode == "hunk" then
      selection_opts.whole_hunk = true
    end
  end
  local metadata, from, to = selected_rows(workspace, selection_opts)
  if not metadata then
    notify(from, vim.log.levels.WARN)
    return false
  end

  local operation
  if kind == "toggle" then
    operation = metadata.section == "staged"
        and { reverse = true, cached = true, label = "Unstaged", focus = "unstaged" }
      or { reverse = false, cached = true, label = "Staged", focus = "staged" }
  elseif kind == "delete" and metadata.section == "staged" then
    operation = { reverse = true, cached = true, label = "Unstaged", focus = "unstaged" }
  elseif kind == "delete" then
    operation = { reverse = true, cached = false, label = "Discarded", destructive = true, focus = "unstaged" }
  else
    return false
  end

  local patch, patch_err = generate_patch(workspace, metadata, from, to, operation.reverse)
  if not patch then
    notify(patch_err, vim.log.levels.WARN)
    return false
  end
  if operation.destructive and opts.confirm ~= false then
    local choice = vim.fn.confirm("Discard the selected unstaged change?", "&Discard\n&Cancel", 2)
    if choice ~= 1 then
      return false
    end
  end
  if operation.destructive and valid_buf(workspace.source_buf) and vim.bo[workspace.source_buf].modified then
    notify("Refusing to discard while the working buffer has unsaved changes", vim.log.levels.ERROR)
    return false
  end

  workspace.applying = true
  show_pending_pane(workspace, operation.focus)
  apply_patch(workspace, patch, operation, function(ok, err)
    if active ~= workspace then
      return
    end
    workspace.applying = false
    if not ok then
      notify(err, vim.log.levels.ERROR)
      M.refresh()
      return
    end
    refresh_source(workspace, not operation.cached)
    M.refresh()
    notify(operation.label .. " selected change")
  end)
  return true
end

function M.toggle_mode()
  local workspace = active
  if not workspace then
    return
  end
  workspace.mode = workspace.mode == "hunk" and "line" or "hunk"
  for key, pane in pairs(workspace.panes or {}) do
    if key ~= "loading" and key ~= "empty" and valid_win(pane.win) then
      local config = vim.api.nvim_win_get_config(pane.win)
      config.footer = " " .. (workspace.mode == "hunk" and "Hunk mode" or "Line mode") .. " "
      config.footer_pos = "right"
      vim.api.nvim_win_set_config(pane.win, config)
    end
  end
end

function M.switch_pane(direction)
  local workspace = active
  if not workspace or not workspace.panes.unstaged or not workspace.panes.staged then
    return
  end
  local current = current_pane(workspace)
  local target = current == workspace.panes.unstaged and workspace.panes.staged or workspace.panes.unstaged
  if direction and direction < 0 then
    target = current == workspace.panes.staged and workspace.panes.unstaged or workspace.panes.staged
  end
  vim.api.nvim_set_current_win(target.win)
end

function M.next_hunk(direction)
  local workspace = active
  if not workspace then
    return
  end
  local row, pane = current_location(workspace)
  if not pane then
    return
  end
  local step = direction < 0 and -1 or 1
  local candidate = row + step
  while candidate >= 1 and candidate <= #pane.rows do
    if pane.rows[candidate] and pane.rows[candidate].kind == "hunk" then
      vim.api.nvim_win_set_cursor(pane.win, { candidate, 0 })
      return
    end
    candidate = candidate + step
  end
  local other = direction > 0 and workspace.panes.staged or workspace.panes.unstaged
  if other and other ~= pane then
    local first = direction > 0 and 1 or #other.rows
    local last = direction > 0 and #other.rows or 1
    for line = first, last, step do
      if other.rows[line] and other.rows[line].kind == "hunk" then
        vim.api.nvim_set_current_win(other.win)
        vim.api.nvim_win_set_cursor(other.win, { line, 0 })
        return
      end
    end
  end
end

function M.close()
  local workspace = active
  if not workspace then
    return
  end
  active = nil
  for _, pane in pairs(workspace.panes or {}) do
    close_pane(pane)
  end
  if valid_win(workspace.source_win) then
    pcall(vim.api.nvim_set_current_win, workspace.source_win)
  end
end

setup_buffer = function(workspace, pane)
  local opts = { buffer = pane.buf, silent = true }
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "Close patch workspace" }))
  vim.keymap.set("n", "<Esc>", M.close, vim.tbl_extend("force", opts, { desc = "Close patch workspace" }))
  vim.keymap.set("n", "r", M.refresh, vim.tbl_extend("force", opts, { desc = "Refresh patch workspace" }))
  vim.keymap.set("n", "<Space>", function() M.action("toggle") end, vim.tbl_extend("force", opts, { desc = "Stage or unstage line" }))
  vim.keymap.set("x", "<Space>", function() M.action("toggle", { visual = true }) end, vim.tbl_extend("force", opts, { desc = "Stage or unstage selected lines" }))
  vim.keymap.set("n", "a", M.toggle_mode, vim.tbl_extend("force", opts, { desc = "Toggle hunk or line mode" }))
  vim.keymap.set("n", "<Tab>", function() M.switch_pane(1) end, vim.tbl_extend("force", opts, { desc = "Switch patch pane" }))
  vim.keymap.set("n", "<S-Tab>", function() M.switch_pane(-1) end, vim.tbl_extend("force", opts, { desc = "Switch patch pane" }))
  vim.keymap.set("n", "dd", function() M.action("delete") end, vim.tbl_extend("force", opts, { desc = "Remove change from section" }))
  vim.keymap.set("x", "d", function() M.action("delete", { visual = true }) end, vim.tbl_extend("force", opts, { desc = "Remove selected lines" }))
  vim.keymap.set("n", "]h", function() M.next_hunk(1) end, vim.tbl_extend("force", opts, { desc = "Next patch hunk" }))
  vim.keymap.set("n", "[h", function() M.next_hunk(-1) end, vim.tbl_extend("force", opts, { desc = "Previous patch hunk" }))
  vim.keymap.set("n", "?", require("agent_diff.help").patch, vim.tbl_extend("force", opts, { desc = "Agent Patch help" }))
end

function M.open()
  if active then
    M.close()
    return nil
  end
  local root, path, source_buf_or_err = source_context()
  if not root then
    notify(path, vim.log.levels.WARN)
    return nil
  end
  local source_win = vim.api.nvim_get_current_win()
  active = {
    root = root,
    path = path,
    source_buf = source_buf_or_err,
    source_win = source_win,
    sections = {},
    panes = {},
    mode = "hunk",
  }
  local loading = ensure_pane(active, "loading", 1, 1, nil)
  loading.lines = { "Loading patch…" }
  loading.rows = { { kind = "loading" } }
  vim.api.nvim_buf_set_lines(loading.buf, 0, -1, false, loading.lines)
  vim.bo[loading.buf].modifiable = false
  vim.api.nvim_set_current_win(loading.win)
  if not M.refresh() then
    M.close()
    return nil
  end
  return active
end

function M.get()
  return active
end

function M.current_pane()
  return active and current_pane(active) or nil
end

function M.row(row)
  local pane = active and current_pane(active) or nil
  return pane and pane.rows[row] or nil
end

return M
