local M = {}

local state = require("agent_review.state")
local target = require("agent_review.target")

local function key(root, file)
  if root and root ~= "" then
    return "root:" .. vim.fs.normalize(root)
  end
  return "file:" .. vim.fs.normalize(file or "unknown")
end

M.key = key

function M.for_annotation(annotation)
  return key(annotation.root, annotation.target and annotation.target.file)
end

function M.current(bufnr)
  local context
  if bufnr then
    context = target.context_for_buffer(bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr)
  else
    context = target.current_context()
  end
  if not context or not context.path then
    return nil
  end
  return key(context.root, context.path)
end

function M.list(scope_key, context)
  if context and context.closed then return {} end
  local store = context and context.state or state
  if not scope_key then
    return store.list()
  end
  local result = {}
  for _, annotation in ipairs(store.list()) do
    if M.for_annotation(annotation) == scope_key then
      table.insert(result, annotation)
    end
  end
  return result
end

function M.current_annotations()
  local current = M.current()
  return current and M.list(current) or {}
end

function M.groups(context)
  local groups = {}
  for _, annotation in ipairs(M.list(nil, context)) do
    local scope_key = M.for_annotation(annotation)
    local group = groups[scope_key]
    if not group then
      local label = annotation.root
        or (annotation.target and vim.fn.fnamemodify(annotation.target.file, ":~"))
        or scope_key
      group = {
        key = scope_key,
        label = label,
        count = 0,
        open = 0,
        resolved = 0,
        stale = 0,
      }
      groups[scope_key] = group
    end
    group.count = group.count + 1
    if annotation.status == "resolved" then
      group.resolved = group.resolved + 1
    else
      group.open = group.open + 1
    end
    if annotation.freshness == "stale" then
      group.stale = group.stale + 1
    end
  end

  local result = vim.tbl_values(groups)
  table.sort(result, function(first, second)
    return first.label < second.label
  end)
  return result
end

return M
