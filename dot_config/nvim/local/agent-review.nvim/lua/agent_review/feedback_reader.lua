local readers = {}
local next_reader = 0
local function new_reader(path, shared)
local M = {}
local tabpage, window, group
local protected = false
local catalog_path, catalog, current, timer = path, nil, nil, nil
local buffers, entries, views, stores = {}, {}, {}, {}
local show_all, switching = false, false
local notice, catalog_error = "", nil
local recent_limit = 20

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "Cannot read " .. path
  end
  local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded or type(value) ~= "table" then
    return nil, "Invalid JSON: " .. path
  end
  return value
end

-- Reject aliases and symlinks, including symlinked parent directories. Entry IDs
-- are opaque identities and are never interpolated into a filesystem path.
local function artifact(path, parent, name, optional)
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" or path:find("%z") then
    return false
  end
  if vim.fs.normalize(path) ~= path or vim.fs.dirname(path) ~= parent
    or (name and vim.fs.basename(path) ~= name) then
    return false
  end
  local stat = vim.uv.fs_lstat(path)
  if not stat then
    return optional == true
  end
  return stat.type == "file" and vim.uv.fs_realpath(path) == path
end

local function nonempty(value)
  return type(value) == "string" and value ~= ""
end

local function load_catalog(path)
  local root = vim.fs.dirname(path)
  if vim.uv.fs_realpath(root) ~= root or not artifact(path, root, nil) then
    return nil, "Invalid feedback catalogue path"
  end
  local value, err = read_json(path)
  if not value then
    return nil, err
  end
  if value.schemaVersion ~= 1 or not nonempty(value.piSessionId)
    or type(value.latestEntryId) ~= "string" or not vim.islist(value.messages)
    or (catalog and value.piSessionId ~= catalog.piSessionId) then
    return nil, "Invalid feedback catalogue identity/schema"
  end
  local ids, paths = {}, {}
  for _, entry in ipairs(value.messages) do
    if type(entry) ~= "table" or not nonempty(entry.entryId) or ids[entry.entryId]
      or type(entry.title) ~= "string" or type(entry.prompt) ~= "string"
      or type(entry.timestamp) ~= "string" or type(entry.onBranch) ~= "boolean"
      or type(entry.finished) ~= "boolean" or type(entry.sourcePath) ~= "string"
      or entry.sourcePath:sub(1, 1) ~= "/" then
      return nil, "Invalid feedback catalogue entry"
    end
    local directory = vim.fs.dirname(entry.sourcePath)
    if directory == root or vim.fs.dirname(directory) ~= root or vim.uv.fs_realpath(directory) ~= directory
      or paths[directory]
      or not artifact(entry.sourcePath, directory, "source.md")
      or not artifact(entry.metadataPath, directory, "metadata.json")
      or not artifact(entry.feedbackStatePath, directory, "annotations.json", true) then
      return nil, "Invalid feedback artifact paths"
    end
    local metadata = read_json(entry.metadataPath)
    if not metadata or metadata.schemaVersion ~= 1 or metadata.reader ~= true
      or metadata.piSessionId ~= value.piSessionId or metadata.assistantMessageId ~= entry.entryId
      or metadata.sourcePath ~= entry.sourcePath or metadata.feedbackDirectory ~= directory
      or not artifact(metadata.feedbackPath, directory, "feedback.json", true) then
      return nil, "Feedback metadata does not match catalogue entry"
    end
    local previous = entries[entry.entryId]
    if previous and (previous.sourcePath ~= entry.sourcePath or previous.metadataPath ~= entry.metadataPath
      or previous.feedbackStatePath ~= entry.feedbackStatePath) then
      return nil, "Feedback snapshot paths changed"
    end
    ids[entry.entryId], paths[directory] = true, true
  end
  if value.latestEntryId ~= "" and not ids[value.latestEntryId] then
    return nil, "Latest feedback entry is missing"
  end
  return value
end

function M.visible_messages()
  local result = {}
  for _, entry in ipairs(catalog and catalog.messages or {}) do
    if show_all or (entry.onBranch and entry.finished and #result < recent_limit) then
      result[#result + 1] = entry
    end
  end
  return result
end

local function clean(text)
  return (text:gsub("[%c]", " "))
end

function M.status()
  local entry = current and entries[current]
  local position = ""
  for i, item in ipairs(M.visible_messages()) do
    if item.entryId == current then
      position = tostring(i) .. "/" .. #M.visible_messages() .. " "
      break
    end
  end
  local newer = catalog and catalog.latestEntryId ~= "" and current ~= catalog.latestEntryId
    and "newer available: <leader>rml | " or ""
  local label = entry and (clean(entry.timestamp) .. " " .. clean(entry.title)) or "Feedback"
  local cue = catalog_error or notice
  return (cue ~= "" and clean(cue) .. " | " or "") .. newer .. position .. label
    .. (show_all and " [all branches/progress]" or " [recent finished]")
end

local function redraw()
  if not M.is_open() then return end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if buffers[vim.api.nvim_win_get_buf(win)] then
      local winbar = "%{v:lua.require'agent_review.feedback_reader'.status()}"
      if vim.wo[win].winbar ~= winbar then vim.wo[win].winbar = winbar end
      -- Lualine owns the statusline. Reassigning it from this poller makes the
      -- footer alternate between two owners; reader notices belong in winbar.
    end
  end
  vim.cmd("redrawstatus")
end

function M.set_notice(text)
  notice = text or ""
  redraw()
end

function M.refresh()
  if not catalog_path then
    return false, "Feedback reader is not open"
  end
  local value, err = load_catalog(catalog_path)
  if not value then
    catalog_error = err
    redraw()
    return false, err
  end
  catalog_error = nil
  catalog = value
  for _, entry in ipairs(value.messages) do
    entries[entry.entryId] = entry
  end
  redraw()
  return true
end

-- This records reader navigation only. Storage selection belongs to context.lua.
function M.activate(bufnr)
  local id = buffers[bufnr]
  if not id then return false end
  current = id
  redraw()
  return true
end

function M.owns(bufnr)
  return buffers[bufnr] ~= nil
end

function M.is_open()
  return tabpage ~= nil and vim.api.nvim_tabpage_is_valid(tabpage)
    and window ~= nil and vim.api.nvim_win_is_valid(window)
end

function M.owns_tab(tab)
  return M.is_open() and tabpage == tab
end

function M.focus(state_path)
  if not M.is_open() then return false end
  if state_path then
    for id, entry in pairs(entries) do
      if entry.feedbackStatePath == state_path then return M.select(id) end
    end
    return false, "Requested feedback draft is not in this catalogue"
  end
  vim.api.nvim_set_current_tabpage(tabpage)
  vim.api.nvim_set_current_win(window)
  return true
end

local function mappings(bufnr)
  local function map(key, action, desc)
    vim.keymap.set("n", key, action, { buffer = bufnr, silent = true, desc = desc })
  end
  map("<leader>rmb", function() M.move(1) end, "Older reply")
  map("<leader>rmn", function() M.move(-1) end, "Newer reply")
  map("<leader>rmp", M.picker, "Find Pi reply")
  map("<leader>rml", M.latest, "Latest completed Pi reply")
end

function M.select(id)
  local entry = entries[id]
  if not entry then
    return false
  end
  if not M.focus() then return false end
  local previous = vim.api.nvim_get_current_buf()
  if buffers[previous] then
    views[buffers[previous]] = vim.fn.winsaveview()
  end
  local bufnr = vim.fn.bufadd(entry.sourcePath)
  buffers[bufnr] = id
  switching = true
  vim.b[bufnr].pi_feedback_disable_lint = true
  vim.fn.bufload(bufnr)
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].autoread = false
  vim.api.nvim_set_current_buf(bufnr)
  local ok = require("agent_review.feedback").attach({ bufnr = bufnr, metadata_path = entry.metadataPath })
  if require("agent_review.context").metadata(bufnr) then
    stores[entry.entryId] = require("agent_review.context").for_buffer(bufnr)
  end
  mappings(bufnr)
  if ok then M.activate(bufnr) end
  if not ok then
    vim.api.nvim_set_current_buf(previous)
  elseif views[id] then
    vim.fn.winrestview(views[id])
  end
  switching = false
  redraw()
  return ok
end

function M.move(delta)
  local visible = M.visible_messages()
  for i, entry in ipairs(visible) do
    if entry.entryId == current then
      local target = visible[i + delta]
      return target and M.select(target.entryId) or false
    end
  end
  -- The current message may have aged out or moved to another branch.
  return visible[1] and M.select(visible[1].entryId) or false
end

function M.latest()
  if not M.refresh() then
    return false
  end
  if catalog.latestEntryId == "" then
    M.set_notice("No completed reply yet")
    return false
  end
  notice = ""
  return M.select(catalog.latestEntryId)
end

function M.toggle_all()
  show_all = not show_all
  redraw()
  return show_all
end

function M.picker_items()
  local items = {}
  for _, entry in ipairs(M.visible_messages()) do
    local ok, lines = pcall(vim.fn.readfile, entry.sourcePath)
    local label = clean(entry.timestamp .. " | " .. entry.title .. " | " .. entry.prompt)
      .. (not entry.onBranch and " [other branch]" or "") .. (not entry.finished and " [progress]" or "")
    items[#items + 1] = {
      entryId = entry.entryId,
      file = entry.sourcePath,
      label = label,
      preview_title = label,
      text = label .. " " .. (ok and table.concat(lines, " ") or ""),
    }
  end
  return items
end

function M.picker()
  if not M.is_open() then return false end
  M.refresh()
  local ok, picker = pcall(require, "snacks.picker")
  if not ok then
    M.set_notice("Snacks picker unavailable")
    return false
  end
  return picker.pick({
    title = "Pi replies: " .. (show_all and "all branches/progress" or "recent 20 finished, current branch") .. " | Ctrl-a toggle all",
    items = M.picker_items(),
    format = function(item) return { { item.label } } end,
    preview = "file",
    previewers = { file = { max_size = math.huge, max_line_length = math.huge, ft = "markdown" } },
    matcher = { sort_empty = false },
    layout = { preset = "default", preview = true },
    actions = {
      feedback_toggle_all = function(p)
        p:close()
        M.toggle_all()
        vim.schedule(M.picker)
      end,
    },
    win = {
      input = { keys = { ["<C-a>"] = { "feedback_toggle_all", mode = { "n", "i" } } } },
      list = { keys = { ["<C-a>"] = "feedback_toggle_all" } },
    },
    confirm = function(p, item)
      p:close()
      if item then
        M.select(item.entryId)
      end
    end,
  })
end

local function stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end
end

function M.dispose()
  stop()
  protected = false
  for _, context in pairs(stores) do
    local ok, err = require("agent_review.context").release(context)
    if not ok then protected = true; notice = err end
  end
end

function M.is_protected()
  return M.is_open() or protected
end

function M.close()
  M.dispose()
  if shared and M.is_open() then
    -- Never let Keep quit a shared editor, even if its other tabs were closed.
    if #vim.api.nvim_list_tabpages() == 1 then vim.cmd("tabnew") end
    vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tabpage))
  end
end

function M.close_view()
  if shared then return M.close() end
  M.dispose()
  if M.focus() then vim.cmd("quit") end
end

local function open_error(message, opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "# Pi feedback reader could not open", "", clean(message), "",
    "No feedback was submitted.", "",
    "Use :q to close, or <leader>rml to retry after fixing the catalogue.",
  })
  vim.bo[bufnr].modifiable = false
  vim.wo.winbar = "Pi feedback reader error"
  vim.keymap.set("n", "<leader>rml", function() M.open(opts) end, { buffer = bufnr, silent = true })
  return false, message
end

function M.open(opts)
  opts = opts or {}
  local ok, err = M.refresh()
  if not ok then
    if shared then return false, err end
    return open_error(err, opts)
  end
  local selected = catalog.latestEntryId
  for _, entry in ipairs(catalog.messages) do
    if entry.entryId == current then selected = current; break end
  end
  local requested = opts.feedback_state_path
  for _, entry in ipairs(catalog.messages) do
    if entry.feedbackStatePath == requested then selected = entry.entryId; break end
  end
  if requested and (not entries[selected] or entries[selected].feedbackStatePath ~= requested) then
    return false, "Requested feedback draft is not in this catalogue"
  end
  if not entries[selected] then return false, "No completed reply yet" end
  require("agent_review").setup()
  local was_open = M.is_open()
  local previous_tab = vim.api.nvim_get_current_tabpage()
  if not was_open then
    if shared then vim.cmd("tabnew") end
    tabpage = vim.api.nvim_get_current_tabpage()
    window = vim.api.nvim_get_current_win()
  end
  stop()
  next_reader = next_reader + 1
  group = vim.api.nvim_create_augroup("AgentFeedbackReader" .. next_reader, { clear = true })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function(event)
      if M.owns_tab(vim.api.nvim_get_current_tabpage()) and buffers[event.buf] then
        views[buffers[event.buf]] = vim.fn.winsaveview()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      if not switching and M.owns_tab(vim.api.nvim_get_current_tabpage()) then
        M.activate(event.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      if not M.is_open() then M.dispose() end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      if event.match ~= tostring(window) then return end
      window = nil
      -- A user may split the reader. Closing one view must not release stores
      -- that another view in its owned tab still uses.
      if vim.api.nvim_tabpage_is_valid(tabpage) then
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
          if tostring(win) ~= event.match and buffers[vim.api.nvim_win_get_buf(win)] then
            window = win
            break
          end
        end
      end
      if not window then M.dispose() end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.dispose })
  if not M.select(selected) then
    if shared and not was_open then
      M.close()
      if vim.api.nvim_tabpage_is_valid(previous_tab) then vim.api.nvim_set_current_tabpage(previous_tab) end
    end
    return false, "Cannot open feedback snapshot"
  end
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if M.is_open() then M.refresh() else M.dispose() end
  end))
  return true
end

return M
end

local API = {}

function API.for_buffer(bufnr)
  for _, reader in pairs(readers) do
    if reader.owns(bufnr) then return reader end
  end
end

local function selected()
  local reader = API.for_buffer(vim.api.nvim_get_current_buf())
  if reader then return reader end
  local tab = vim.api.nvim_get_current_tabpage()
  for _, reader in pairs(readers) do
    if reader.owns_tab(tab) then return reader end
  end
end

function API.open(opts)
  opts = opts or {}
  local path = opts.catalog_path or vim.env.PI_FEEDBACK_CATALOG
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
    return false, "PI_FEEDBACK_CATALOG must be an absolute path"
  end
  local reader = readers[path] or new_reader(path, opts.shared == true)
  readers[path] = reader
  return reader.open(opts)
end

function API.remote(request)
  -- A new reader file can be loaded into an old process after installation.
  -- Never combine it with the old global store or reload process state.
  if require("agent_review").feedback_context_version ~= 1 then
    return { ok = false, error = "Restart Neovim to enable isolated feedback contexts" }
  end
  if type(request) ~= "table" or not ({ open = true, focus = true, status = true })[request.action] then
    return { ok = false, error = "Unsupported feedback reader request" }
  end
  local path = request.cataloguePath
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" or path:find("%z") or vim.fs.normalize(path) ~= path then
    return { ok = false, error = "cataloguePath must be a normalized absolute path" }
  end
  if request.feedbackStatePath ~= nil and type(request.feedbackStatePath) ~= "string" then
    return { ok = false, error = "feedbackStatePath must be a path string" }
  end
  local reader = readers[path]
  if request.action == "open" then
    reader = reader or new_reader(path, true)
    readers[path] = reader
    local called, ok, err = pcall(reader.open, { feedback_state_path = request.feedbackStatePath })
    if not called or not ok then return { ok = false, error = tostring(called and err or ok) } end
  elseif request.action == "focus" and reader and reader.is_protected() then
    -- A failed final save retains the reader even after its tab closes. Reopen
    -- that retained reader so /feedback can recover, rather than silently
    -- focusing the editor without a reader or permitting draft deletion.
    local called, ok, err
    if reader.is_open() then
      called, ok, err = pcall(reader.focus, request.feedbackStatePath)
    else
      called, ok, err = pcall(reader.open, { feedback_state_path = request.feedbackStatePath })
    end
    if not called or not ok then return { ok = false, error = tostring(called and err or ok) } end
  end
  return {
    ok = true,
    open = reader ~= nil and reader.is_protected() or false,
    paneId = vim.env.HERDR_PANE_ID,
    socketPath = vim.env.HERDR_SOCKET_PATH,
  }
end

return setmetatable(API, {
  __index = function(_, method)
    return function(...)
      local reader = selected()
      if reader then return reader[method](...) end
      if method == "status" then return "" end
      return false
    end
  end,
})
