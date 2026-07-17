local M = {}

local function command_error(output, fallback)
  output = vim.trim(output or "")
  return output ~= "" and output or fallback
end

function M.run(command)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    return nil, command_error(output, "command failed")
  end
  return output, nil
end

local function herdr_bin()
  return vim.env.HERDR_BIN_PATH or "herdr"
end

function M.herdr(...)
  local command = { herdr_bin() }
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    table.insert(command, arg)
  end
  return M.run(command)
end

return M
