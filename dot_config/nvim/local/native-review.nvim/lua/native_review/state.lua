local M = {}

local annotations = {}
local next_id = 1

function M.add(annotation)
  if not annotation.id then
    repeat
      annotation.id = string.format("review-%d", next_id)
      next_id = next_id + 1
    until not M.get(annotation.id)
  end
  table.insert(annotations, annotation)
  return annotation
end

function M.list()
  return annotations
end

function M.get(id)
  for _, annotation in ipairs(annotations) do
    if annotation.id == id then
      return annotation
    end
  end
end

function M.remove(id)
  for index, annotation in ipairs(annotations) do
    if annotation.id == id then
      table.remove(annotations, index)
      return annotation
    end
  end
  return false
end

function M.clear()
  local previous = annotations
  annotations = {}
  return previous
end

return M
