local M = {}

local ignored_allowlist = {
  "**/.env",
  "**/.env.*",
  "**/opencode.json",
  "**/.workmux.yaml",
  "**/.opencode/**",
  "**/.claude/**",
}

local PICKER_BASE = {
  finder = false,
}

function M.get_current_dir()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.fn.expand("%:p:h")
  if vim.bo[buf].filetype == "oil" then
    path = path:gsub("^oil://", "")
  end
  return path
end

local function rg_glob_args(globs)
  local args = {}
  for _, glob in ipairs(globs) do
    vim.list_extend(args, { "-g", glob })
  end
  return args
end

function M.pick_with_ignored_allowlist(command, source, opts)
  opts = opts or {}

  local normal = {
    source = source,
    cwd = opts.cwd,
    hidden = true,
    ignored = false,
  }

  local allowlisted_ignored = {
    source = source,
    cwd = opts.cwd,
    hidden = true,
    ignored = true,
  }

  if source == "files" then
    allowlisted_ignored.cmd = "rg"
    allowlisted_ignored.args = rg_glob_args(ignored_allowlist)
  else
    allowlisted_ignored.glob = ignored_allowlist
  end

  local pick_opts = vim.tbl_deep_extend("force", {}, PICKER_BASE, {
    multi = { normal, allowlisted_ignored },
  })

  if source == "files" then
    pick_opts.transform = "unique_file"
  end

  return LazyVim.pick(command, pick_opts)()
end

return M
