local M = {}

local annotations = {}
local next_id = 1

function M.add(annotation)
  annotation.id = annotation.id or string.format("review-%d", next_id)
  next_id = next_id + 1
  table.insert(annotations, annotation)
  return annotation
end

function M.list()
  return annotations
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
