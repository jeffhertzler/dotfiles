local M = {}

local installed = false
local core_git = require("codediff.core.git")

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Agent Diff" })
end

local function copy_files(items)
  local files = {}
  for _, item in ipairs(items or {}) do
    table.insert(files, {
      path = item.path,
      old_path = item.old_path,
      status = item.status,
    })
  end
  return files
end

local function union_files(...)
  local result, seen = {}, {}
  for _, items in ipairs({ ... }) do
    for _, item in ipairs(items or {}) do
      if not seen[item.path] then
        seen[item.path] = true
        table.insert(result, {
          path = item.path,
          old_path = item.old_path,
          status = item.status,
        })
      end
    end
  end
  return result
end

local function launch(root, files, original, modified, focus, opts, reload_files)
  if opts and opts.only and focus then
    local unfiltered_reload = reload_files
    local function only_focused(items)
      return vim.tbl_filter(function(file)
        return file.path == focus
      end, items or {})
    end
    files = only_focused(files)
    if unfiltered_reload then
      reload_files = function(callback)
        unfiltered_reload(function(err, items)
          callback(err, not err and only_focused(items) or nil)
        end)
      end
    end
  end
  if #files == 0 then
    notify("No changed files")
    return
  end
  require("agent_diff").open_changeset({
    root = root,
    files = files,
    focus_file = focus,
    original_revision = original,
    modified_revision = modified,
    layout = "inline",
    explorer = #files > 1,
    on_close = opts and opts.on_close and opts.on_close.fn or nil,
    park_owner = opts and opts.park_owner or nil,
    reload_files = reload_files,
  })
end

local function revision_files(root, original, modified, focus, opts)
  local function load(callback)
    core_git.get_diff_revisions(original, modified, root, function(err, result)
      callback(err, not err and copy_files(result.unstaged) or nil)
    end)
  end
  load(function(err, files)
    vim.schedule(function()
      if err then
        notify(err, vim.log.levels.ERROR)
      else
        launch(root, files, original, modified, focus, opts, load)
      end
    end)
  end)
end

local function status_files(root, section, focus, opts)
  local function load(callback)
    core_git.get_status(root, function(err, result)
      if err then
        callback(err)
      elseif section == "unstaged" then
        callback(nil, copy_files(result.unstaged))
      elseif section == "staged" then
        callback(nil, copy_files(result.staged))
      else
        callback(nil, union_files(result.staged, result.unstaged))
      end
    end)
  end
  load(function(err, files)
    vim.schedule(function()
      if err then
        notify(err, vim.log.levels.ERROR)
        return
      end
      if section == "unstaged" then
        launch(root, files, "INDEX", "WORKING", focus, opts, load)
      elseif section == "staged" then
        launch(root, files, "HEAD", "INDEX", focus, opts, load)
      else
        launch(root, files, "HEAD", "WORKING", focus, opts, load)
      end
    end)
  end)
end

local function parse_range(value)
  local base, target = value:match("^(.-)%.%.%.(.-)$")
  if base then
    return "triple", base, target ~= "" and target or "HEAD"
  end
  base, target = value:match("^(.-)%.%.(.-)$")
  if base then
    return "double", base, target
  end
end

local function extract_commit(value)
  if type(value) ~= "string" then
    return nil
  end
  return value:match("^([0-9a-fA-F]+)") or value:match("(stash@{%d+})") or vim.trim(value)
end

function M.open(section, item, opts)
  opts = opts or {}
  local ok_status, status = pcall(require, "neogit.buffers.status")
  local status_instance = ok_status and status.instance() or nil
  local from_status = section == "staged"
    or section == "unstaged"
    or section == "merge"
    or section == "worktree"
    or section == "conflict"
  local status_buffer = status_instance and status_instance.buffer or nil
  local status_visible = status_buffer
    and status_buffer.win_handle
    and vim.api.nvim_win_is_valid(status_buffer.win_handle)
    and vim.api.nvim_win_get_buf(status_buffer.win_handle) == status_buffer.handle
  if status_buffer and (from_status or status_visible) then
    opts.park_owner = status_buffer
  end
  local root = require("neogit.lib.git").repo.worktree_root
  if not root then
    return notify("Git root is unavailable", vim.log.levels.ERROR)
  end

  if section == "staged" or section == "unstaged" or section == "merge" then
    return status_files(root, section, type(item) == "string" and item or nil, opts)
  elseif section == "worktree" or (section == nil and item == nil) then
    return status_files(root, "worktree", nil, opts)
  elseif section == "range" and type(item) == "string" then
    local kind, first, second = parse_range(item)
    if kind == "double" then
      return revision_files(root, first, second, nil, opts)
    elseif kind == "triple" then
      return core_git.get_merge_base(first, second, root, function(err, merge_base)
        if err then
          return vim.schedule(function()
            notify(err, vim.log.levels.ERROR)
          end)
        end
        core_git.resolve_revision(second, root, function(resolve_err, target)
          vim.schedule(function()
            if resolve_err then
              notify(resolve_err, vim.log.levels.ERROR)
            else
              revision_files(root, merge_base, target, nil, opts)
            end
          end)
        end)
      end)
    end
  elseif section == "recent" or section == "log" or section == "commit" or section == "stashes" or section == nil then
    if type(item) == "table" and #item > 1 then
      local first = extract_commit(item[1])
      local last = extract_commit(item[#item])
      if first and last then
        return revision_files(root, first, last, nil, opts)
      end
    end
    local commit = extract_commit(type(item) == "table" and item[1] or item)
    if commit then
      return core_git.resolve_revision(commit, root, function(err, resolved)
        vim.schedule(function()
          if err then
            notify(err, vim.log.levels.ERROR)
          else
            revision_files(root, resolved .. "^", resolved, nil, opts)
          end
        end)
      end)
    end
  end
  notify("This diff context is not supported yet", vim.log.levels.WARN)
end

local function parse_region(lines, first_line)
  local old, new, old_rows, new_rows = {}, {}, {}, {}
  for index, line in ipairs(lines) do
    local prefix, text = line:sub(1, 1), line:sub(2)
    local row = first_line + index - 1
    if prefix == " " then
      table.insert(old, text)
      table.insert(new, text)
    elseif prefix == "-" then
      table.insert(old, text)
      old_rows[#old] = row
    elseif prefix == "+" then
      table.insert(new, text)
      new_rows[#new] = row
    end
  end
  return old, new, old_rows, new_rows
end

local function setup_highlighter()
  local highlights = require("neogit.lib.diff_highlights")
  local original_apply = highlights.apply
  highlights.apply = function(buf, regions)
    original_apply(buf, regions)
    local namespace = buf:create_namespace("NeogitDiffHighlight")
    local started = vim.uv.hrtime()
    for _, region in ipairs(regions) do
      if (vim.uv.hrtime() - started) / 1e6 > 100 then
        break
      end
      local old, new, old_rows, new_rows = parse_region(
        buf:get_lines(region.first_line, region.last_line, false),
        region.first_line
      )
      if #old > 0 or #new > 0 then
        local ok, result = pcall(require("codediff.core.diff").compute_diff, old, new, {
          max_computation_time_ms = 50,
          compute_moves = false,
        })
        if ok then
          require("agent_diff.ranges").apply(buf.handle, namespace, result, old, new, old_rows, new_rows, {
            old_highlight = "CodeDiffCharDelete",
            new_highlight = "CodeDiffCharInsert",
            column_offset = 1,
            priority = 220,
          })
        end
      end
    end
  end
end

function M.status()
  local diff = require("agent_diff")
  local session = diff.get_session()
  local returns_to_status = session and session.park_owner and session.park_owner.name == "NeogitStatus"
  if session then
    diff.close()
  end
  if not returns_to_status then
    vim.cmd("Neogit")
  end
end

function M.setup()
  if installed then
    return
  end
  installed = true
  setup_highlighter()
  -- Neogit only supports named Diffview/CodeDiff providers. Keep its full
  -- DiffPopup and replace the CodeDiff provider's open function with the thin
  -- no-tab Agent Diff changeset host.
  require("neogit.integrations.codediff").open = M.open
end

return M
