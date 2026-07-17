local M = {}

local state = require("native_review.state")

local function format_location(annotation)
  local target = annotation.target
  local side = ({ old = "~", new = "+", working = " " })[target.side] or " "
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
  return string.format("%s %s:%s", side, target.file, range)
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
    vim.notify("Open the annotation's diff before navigating to it", vim.log.levels.INFO, { title = "Native Review" })
    return
  end

  local original_buf, modified_buf = lifecycle.get_buffers(tabpage)
  local original_win, modified_win = lifecycle.get_windows(tabpage)
  local side = annotation.target.side
  local bufnr = side == "old" and original_buf or modified_buf
  local winid = side == "old" and original_win or modified_win

  if lifecycle.get_layout(tabpage) == "inline" and side == "old" then
    vim.notify("Old-side inline navigation is part of the next spike", vim.log.levels.INFO, { title = "Native Review" })
    return
  end
  if not (winid and vim.api.nvim_win_is_valid(winid) and bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end

  local context = require("native_review.target").context_for_buffer(bufnr)
  if not context or context.path ~= annotation.target.file then
    vim.notify("Select the annotation's file in CodeDiff first", vim.log.levels.INFO, { title = "Native Review" })
    return
  end

  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(winid, {
    annotation.target.start_line,
    math.max(0, (annotation.target.start_col or 1) - 1),
  })
end

function M.open(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local annotations = state.list()
  if #annotations == 0 then
    vim.notify("No annotations in this review", vim.log.levels.INFO, { title = "Native Review" })
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
      title = "Review annotations",
      items = items,
      format = "text",
      focus = "list",
      layout = { preset = "select", preview = false },
      actions = {
        remove_annotation = function(picker, item)
          picker:close()
          if item and require("native_review").remove(item.annotation.id) then
            vim.schedule(function()
              if #state.list() > 0 then
                M.open(tabpage)
              end
            end)
          end
        end,
      },
      win = {
        list = {
          keys = {
            d = { "remove_annotation", desc = "Remove annotation" },
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

return M
