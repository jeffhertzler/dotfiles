-- Select storage here, not in adapters or BufEnter handlers. Background work
-- and asynchronous editors retain these instances instead of selecting again.
local M = {}
local ordinary, feedback = nil, {}

function M.proxy(name, new)
  return setmetatable({ new = new }, {
    __index = function(_, method)
      return function(...)
        return M.for_buffer()[name][method](...)
      end
    end,
  })
end

local function create()
  local context = {}
  context.state = require("agent_review.state").new()
  context.sessions = require("agent_review.sessions").new(context)
  context.persistence = require("agent_review.persistence").new(context)
  return context
end

function M.ordinary()
  if not ordinary then ordinary = create() end
  return ordinary
end

function M.metadata(bufnr)
  if not bufnr or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  return vim.b[bufnr].pi_feedback
end

function M.for_buffer(bufnr)
  local metadata = M.metadata(bufnr)
  if not metadata then return M.ordinary() end
  local path = metadata.feedbackDirectory .. "/annotations.json"
  if not feedback[path] then
    local context = create()
    feedback[path] = context
    context.persistence.setup({ path = path })
    -- A malformed draft is read-only until attachment can reload it. Otherwise
    -- direct :buffer navigation could accept edits that can never be saved.
    context.closed = context.persistence.status().load_failed
  end
  return feedback[path]
end

-- Internal callers retain the context itself across picker/input callbacks.
-- A wiped or repurposed buffer must not select a different annotation store.
function M.for_operation(opts)
  return opts and opts._context or M.for_buffer(opts and opts.bufnr)
end

function M.attach(bufnr, metadata)
  vim.b[bufnr].pi_feedback = vim.deepcopy(metadata)
  local path = metadata.feedbackDirectory .. "/annotations.json"
  if feedback[path] and feedback[path].closed then feedback[path] = nil end
  local context = M.for_buffer(bufnr)
  local status = context.persistence.status()
  if status.load_failed then
    local ok, err = context.persistence.load()
    if not ok then context.closed = true; return nil, err end
    context.closed = false
  end
  return context
end

function M.release(context)
  if context == ordinary or context.closed then return true end
  local ok, err = context.persistence.dispose()
  if not ok then return false, err end
  context.closed = true
  return true
end

function M.save_all()
  local stores = { M.ordinary() }
  for _, context in pairs(feedback) do stores[#stores + 1] = context end
  for _, context in ipairs(stores) do context.persistence.save_now() end
end

return M
