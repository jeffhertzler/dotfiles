local M = {}

local function close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

function M.open(title, lines)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(math.max(width + 2, 36), math.max(36, vim.o.columns - 6))
  local height = math.min(#lines, math.max(1, vim.o.lines - 6))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "AgentDiffHelp"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
    zindex = 250,
  })
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = table.concat({
    "Normal:SnacksInputNormal",
    "NormalFloat:SnacksInputNormal",
    "FloatBorder:SnacksInputBorder",
    "FloatTitle:SnacksInputTitle",
  }, ",")
  for _, lhs in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", lhs, function() close(win) end, { buffer = buf, silent = true, nowait = true })
  end
  return win
end

function M.diff()
  return M.open("Agent Diff Help", {
    "<leader>gd   Toggle inline diff",
    "<leader>gD   Toggle side-by-side diff",
    "<leader>gw   Toggle patch workspace",
    "<leader>b    Toggle changed-files sidebar",
    "[f / ]f      Previous / next changed file",
    "<leader>ra   Add review annotation",
    "?            Show or close this help",
  })
end

function M.patch()
  return M.open("Agent Patch Help", {
    "Tab / S-Tab  Switch staged / unstaged pane",
    "Space        Stage / unstage current line or hunk",
    "Visual Space Stage / unstage selected lines",
    "a            Toggle hunk / line mode",
    "dd           Unstage or discard hunk",
    "Visual d     Unstage or discard selected lines",
    "[h / ]h      Previous / next hunk",
    "<leader>ra   Review the exact patch row",
    "r            Refresh",
    "q / Esc      Close patch workspace",
    "?            Show or close this help",
  })
end

return M
