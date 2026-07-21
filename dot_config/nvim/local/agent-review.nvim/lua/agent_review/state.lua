local M = {}

local annotations = {}
local next_id = 1
local listeners = {}

local function notify_change()
  for _, listener in ipairs(listeners) do
    listener(annotations)
  end
end

local function update_next_id(annotation)
  local number = annotation.id and annotation.id:match("^review%-(%d+)$")
  if number then
    next_id = math.max(next_id, tonumber(number) + 1)
  end
end

function M.add(annotation)
  if not annotation.id then
    repeat
      annotation.id = string.format("review-%d", next_id)
      next_id = next_id + 1
    until not M.get(annotation.id)
  end
  table.insert(annotations, annotation)
  update_next_id(annotation)
  notify_change()
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
      notify_change()
      return annotation
    end
  end
  return false
end

function M.clear()
  local previous = annotations
  annotations = {}
  next_id = 1
  notify_change()
  return previous
end

function M.replace(loaded)
  annotations = loaded or {}
  next_id = 1
  for _, annotation in ipairs(annotations) do
    update_next_id(annotation)
  end
end

function M.changed()
  notify_change()
end

function M.on_change(listener)
  table.insert(listeners, listener)
  return function()
    for index, candidate in ipairs(listeners) do
      if candidate == listener then
        table.remove(listeners, index)
        return
      end
    end
  end
end

return M
