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

local function rg_allowlisted_files_args()
  local args = {
    "--files",
    "--no-messages",
    "--hidden",
    "--no-ignore",
  }
  for _, glob in ipairs(ignored_allowlist) do
    vim.list_extend(args, { "-g", glob })
  end
  return args
end

local function files_transform(item, ctx)
  if item.source_id == 2 then
    item.file = item.file or item.text
    item.cwd = item.cwd or ctx.filter.cwd
  end
  return require("snacks.picker.transform").unique_file(item, ctx)
end

local function grep_filter_transform(_picker, filter)
  filter.pattern = filter.search
end

function M.pick_with_ignored_allowlist(_command, source, opts)
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
    normal.cmd = "fd"
    allowlisted_ignored.finder = "proc"
    allowlisted_ignored.cmd = "rg"
    allowlisted_ignored.args = rg_allowlisted_files_args()
    allowlisted_ignored.notify = false
  else
    allowlisted_ignored.glob = ignored_allowlist
  end

  local pick_opts = vim.tbl_deep_extend("force", {}, PICKER_BASE, {
    multi = { normal, allowlisted_ignored },
  })

  if source == "files" then
    pick_opts.transform = files_transform
  elseif source == "grep" or source == "grep_word" then
    pick_opts.matcher = {
      frecency = false,
      history_bonus = false,
    }
    pick_opts.filter = {
      transform = grep_filter_transform,
    }
  end

  return Snacks.picker.pick(source, pick_opts)
end

return M
