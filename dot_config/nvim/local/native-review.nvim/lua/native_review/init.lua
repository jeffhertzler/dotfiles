local M = {}

local state = require("native_review.state")
local target = require("native_review.target")
local render = require("native_review.render")

local initialized = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Native Review" })
end

local function create_annotation(capture, body)
  body = vim.trim(body or "")
  if body == "" then
    return nil
  end

  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local annotation = state.add({
    author = { kind = "human", name = vim.env.USER or "human" },
    body = body,
    kind = "note",
    status = "open",
    root = capture.root,
    host = capture.host,
    revision = capture.revision,
    target = capture.target,
    anchor = capture.anchor,
    created_at = now,
    updated_at = now,
  })
  render.refresh_buffer(capture.bufnr)
  notify("Added annotation " .. annotation.id)
  return annotation
end

function M.add(opts)
  opts = opts or {}
  local capture = target.capture(opts)
  if not capture then
    return nil
  end

  if opts.body ~= nil then
    return create_annotation(capture, opts.body)
  end

  vim.ui.input({ prompt = "Annotation: " }, function(body)
    if body then
      create_annotation(capture, body)
    end
  end)
end

function M.list()
  require("native_review.picker").open()
end

function M.clear()
  render.clear_all()
  state.clear()
  notify("Cleared review annotations")
end

function M.annotations()
  return state.list()
end

function M.refresh(tabpage)
  render.refresh(tabpage)
end

function M.setup()
  if initialized then
    return
  end
  initialized = true

  render.setup_highlights()
  local group = vim.api.nvim_create_augroup("NativeReview", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = render.setup_highlights,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
    callback = function(event)
      local tabpage = event.data and event.data.tabpage or vim.api.nvim_get_current_tabpage()
      vim.defer_fn(function()
        render.refresh(tabpage)
      end, 100)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(event)
      vim.schedule(function()
        render.refresh_buffer(event.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function()
      vim.defer_fn(function()
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(winid) then
            render.refresh_buffer(vim.api.nvim_win_get_buf(winid))
          end
        end
      end, 50)
    end,
  })

  vim.api.nvim_create_user_command("NativeReviewAdd", function()
    M.add()
  end, { desc = "Annotate the current CodeDiff line" })
  vim.api.nvim_create_user_command("NativeReviewList", M.list, { desc = "List review annotations" })
  vim.api.nvim_create_user_command("NativeReviewClear", M.clear, { desc = "Clear review annotations" })
end

return M
