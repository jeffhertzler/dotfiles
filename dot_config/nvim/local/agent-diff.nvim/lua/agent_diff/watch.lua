local M = {}

function M.stop(watcher)
  if not watcher then
    return
  end
  if watcher.timer then
    watcher.timer:stop()
    if not watcher.timer:is_closing() then
      watcher.timer:close()
    end
  end
  if watcher.event then
    watcher.event:stop()
    if not watcher.event:is_closing() then
      watcher.event:close()
    end
  end
end

local function start(parent, basename, callback, delay)
  if not parent or not vim.uv.fs_stat(parent) then
    return nil
  end
  local watcher = {
    event = vim.uv.new_fs_event(),
    timer = vim.uv.new_timer(),
  }
  if not watcher.event or not watcher.timer then
    M.stop(watcher)
    return nil
  end
  local ok = watcher.event:start(parent, {}, function(err, filename)
    if err or (basename and filename and filename ~= basename) then
      return
    end
    watcher.timer:stop()
    watcher.timer:start(delay or 150, 0, vim.schedule_wrap(callback))
  end)
  if not ok then
    M.stop(watcher)
    return nil
  end
  return watcher
end

function M.file(path, callback, delay)
  return start(vim.fs.dirname(path), vim.fs.basename(path), callback, delay)
end

function M.directory(path, callback, delay)
  return start(path, nil, callback, delay)
end

return M
