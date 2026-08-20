local M = {}

local function format_location(annotation)
  local target = annotation.target
  local side = ({ old = "~", new = "+", working = " " })[target.side] or " "
  local state_icon = annotation.status == "resolved" and "✓"
    or annotation.freshness == "stale" and "!"
    or annotation.freshness == "reanchored" and "↪"
    or " "
  local range
  if target.start_col then
    range = string.format("%d:%d", target.start_line, target.start_col)
    if target.start_line ~= target.end_line or target.start_col ~= target.end_col then
      range = range .. string.format("-%d:%d", target.end_line, target.end_col)
    end
  else
    range = tostring(target.start_line)
    if target.start_line ~= target.end_line then
      range = range .. "-" .. target.end_line
    end
  end
  return string.format("%s%s %s:%s", state_icon, side, target.file, range)
end

local function navigate(tabpage, annotation)
  if annotation.target.side == "working" then
    local path = annotation.root and (annotation.root .. "/" .. annotation.target.file) or annotation.target.file
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    vim.api.nvim_win_set_cursor(0, {
      annotation.target.start_line,
      math.max(0, (annotation.target.start_col or 1) - 1),
    })
    return
  end

  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok or not lifecycle.get_session(tabpage) then
    return
  end

  local original_buf, modified_buf = lifecycle.get_buffers(tabpage)
  local original_win, modified_win = lifecycle.get_windows(tabpage)
  local side = annotation.target.side
  local bufnr = side == "old" and original_buf or modified_buf
  local winid = side == "old" and original_win or modified_win

  if lifecycle.get_layout(tabpage) == "inline" and side == "old" then
    return
  end
  if not (winid and vim.api.nvim_win_is_valid(winid) and bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end

  local context = require("agent_review.target").context_for_buffer(bufnr)
  if not context or context.path ~= annotation.target.file then
    return
  end

  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(winid, {
    annotation.target.start_line,
    math.max(0, (annotation.target.start_col or 1) - 1),
  })
end

function M.open(opts)
  if type(opts) == "number" then
    opts = { tabpage = opts }
  end
  opts = opts or {}
  local tabpage = opts.tabpage or vim.api.nvim_get_current_tabpage()
  local scope = require("agent_review.scope")
  local sessions = require("agent_review.sessions")
  local scope_key = opts.all and nil or (opts.scope or scope.current())
  local active_session = opts.session and sessions.get(opts.session) or (not opts.all and not opts.scope and sessions.current(scope_key))
  local annotations = opts.annotations
    or (opts.all and scope.list())
    or (active_session and sessions.annotations(active_session.id))
    or (opts.scope and scope.list(scope_key))
    or {}
  if #annotations == 0 then
    return
  end

  local items = {}
  for _, annotation in ipairs(annotations) do
    table.insert(items, {
      annotation = annotation,
      text = string.format("%s  %s", format_location(annotation), annotation.body:gsub("\n", " ")),
    })
  end

  local ok, snacks = pcall(require, "snacks")
  if ok then
    snacks.picker({
      title = opts.title
        or (opts.all and "All review annotations")
        or (active_session and active_session.name)
        or "Review annotations",
      items = items,
      format = "text",
      focus = "list",
      layout = { preset = "select", preview = false },
      actions = {
        toggle_resolved = function(picker, item)
          picker:close()
          if item then
            local review = require("agent_review")
            if item.annotation.status == "resolved" then
              review.annotation.reopen(item.annotation.id)
            else
              review.annotation.resolve(item.annotation.id)
            end
            vim.schedule(function()
              M.open(opts)
            end)
          end
        end,
        edit_annotation = function(picker, item)
          picker:close()
          if item then
            require("agent_review").annotation.edit(item.annotation.id)
          end
        end,
        remove_annotation = function(picker, item)
          picker:close()
          if item and require("agent_review").annotation.remove(item.annotation.id) then
            vim.schedule(function()
              local remaining = active_session and sessions.annotations(active_session.id) or scope.list(scope_key)
              if #remaining > 0 then
                M.open(opts)
              end
            end)
          end
        end,
      },
      win = {
        list = {
          keys = {
            d = { "remove_annotation", desc = "Remove annotation" },
            e = { "edit_annotation", desc = "Edit annotation" },
            r = { "toggle_resolved", desc = "Resolve or reopen annotation" },
          },
        },
      },
      confirm = function(picker, item)
        picker:close()
        if item then
          navigate(tabpage, item.annotation)
        end
      end,
    })
    return
  end

  vim.ui.select(items, {
    prompt = "Review annotations",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      navigate(tabpage, choice.annotation)
    end
  end)
end

function M.sessions(opts)
  opts = opts or {}
  local store = require("agent_review.sessions")
  local workspace = opts.workspace or require("agent_review.scope").current()
  if not workspace then
    return
  end
  local available = store.list(workspace, { include_archived = true })
  if #available == 0 then
    return
  end

  local active = store.current(workspace)
  local items = {}
  for _, session in ipairs(available) do
    local counts = store.counts(session.id)
    local marker = session.status == "archived" and "□" or (active and active.id == session.id and "●" or "○")
    table.insert(items, {
      session = session,
      text = string.format(
        "%s %s  %d open · %d resolved · %d stale  [%s → %s]",
        marker,
        session.name,
        counts.open,
        counts.resolved,
        counts.stale,
        session.base_revision or "working",
        session.target_revision or "WORKING"
      ),
    })
  end

  local ok, snacks = pcall(require, "snacks")
  if ok then
    snacks.picker({
      title = opts.title or "Review sessions",
      items = items,
      format = "text",
      focus = "list",
      layout = { preset = "select", preview = false },
      actions = {
        toggle_archive = function(picker, item)
          picker:close()
          if item then
            if item.session.status == "archived" then
              store.activate(item.session.id)
            else
              store.archive(item.session.id)
            end
            require("agent_review.render").refresh_visible()
            vim.schedule(function()
              M.sessions(opts)
            end)
          end
        end,
      },
      win = {
        list = {
          keys = {
            a = { "toggle_archive", desc = "Archive or restore session" },
          },
        },
      },
      confirm = function(picker, item)
        picker:close()
        if item then
          store.activate(item.session.id)
          require("agent_review.render").refresh_visible()
          M.open({ session = item.session.id, title = item.session.name })
        end
      end,
    })
    return
  end

  vim.ui.select(items, {
    prompt = "Review sessions",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      store.activate(choice.session.id)
      require("agent_review.render").refresh_visible()
      M.open({ session = choice.session.id, title = choice.session.name })
    end
  end)
end

function M.workspaces()
  local groups = require("agent_review.scope").groups()
  if #groups == 0 then
    return
  end

  local items = {}
  for _, group in ipairs(groups) do
    table.insert(items, {
      group = group,
      text = string.format("%s  %d open · %d resolved · %d stale", group.label, group.open, group.resolved, group.stale),
    })
  end

  local ok, snacks = pcall(require, "snacks")
  if ok then
    snacks.picker({
      title = "Review workspaces",
      items = items,
      format = "text",
      focus = "list",
      layout = { preset = "select", preview = false },
      confirm = function(picker, item)
        picker:close()
        if item then
          M.sessions({ workspace = item.group.key, title = item.group.label })
        end
      end,
    })
    return
  end

  vim.ui.select(items, {
    prompt = "Review workspaces",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      M.sessions({ workspace = choice.group.key, title = choice.group.label })
    end
  end)
end

return M
