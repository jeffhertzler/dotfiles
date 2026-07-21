local M = {}

local namespace = vim.api.nvim_create_namespace("agent-diff-gitsigns-preview")

local function current_hunk(bufnr)
  local hunks = require("gitsigns").get_hunks(bufnr) or {}
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local nearest
  for _, hunk in ipairs(hunks) do
    local start_line = math.max(1, hunk.added.start)
    local end_line = start_line + math.max(1, hunk.added.count) - 1
    if cursor >= start_line and cursor <= end_line then
      return hunk
    end
    local distance = math.abs(cursor - start_line)
    if not nearest or distance < nearest.distance then
      nearest = { hunk = hunk, distance = distance }
    end
  end
  return nearest and nearest.distance <= 1 and nearest.hunk or nil
end

local function clear(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
end

function M.preview_hunk()
  local bufnr = vim.api.nvim_get_current_buf()
  clear(bufnr)
  local hunk = current_hunk(bufnr)
  if not hunk then
    vim.notify("No Git hunk at the cursor", vim.log.levels.INFO, { title = "Agent Diff" })
    return
  end

  local old = hunk.removed.lines or {}
  local new = hunk.added.lines or {}
  local ok, result = pcall(require("codediff.core.diff").compute_diff, old, new, {
    max_computation_time_ms = 100,
    compute_moves = false,
  })
  if not ok then
    vim.notify(result, vim.log.levels.ERROR, { title = "Agent Diff" })
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_row = math.max(0, math.min(hunk.added.start - 1, line_count - 1))
  for offset = 0, hunk.added.count - 1 do
    local row = start_row + offset
    if row < line_count then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        end_row = row + 1,
        hl_group = "CodeDiffLineInsert",
        hl_eol = true,
        priority = 230,
      })
    end
  end

  local ranges = require("agent_diff.ranges")
  local new_rows = {}
  for i = 1, #new do
    new_rows[i] = start_row + i - 1
  end
  ranges.apply(bufnr, namespace, result, old, new, {}, new_rows, {
    new_highlight = "CodeDiffCharInsert",
    priority = 240,
  })

  if #old > 0 then
    local virtual_lines = {}
    for i, text in ipairs(old) do
      table.insert(
        virtual_lines,
        ranges.chunks(text, ranges.spans(result, "original", i, old), "CodeDiffLineDelete", "CodeDiffCharDelete")
      )
    end
    vim.api.nvim_buf_set_extmark(bufnr, namespace, start_row, 0, {
      virt_lines = virtual_lines,
      virt_lines_above = true,
      virt_lines_overflow = "scroll",
      priority = 230,
    })
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
    buffer = bufnr,
    once = true,
    callback = function()
      clear(bufnr)
    end,
  })
end

function M.setup_buffer(bufnr)
  vim.keymap.set("n", "<leader>ghp", M.preview_hunk, {
    buffer = bufnr,
    desc = "Preview Hunk (Agent Diff)",
  })
  vim.keymap.set("n", "<leader>ghd", function()
    require("agent_diff").open_side("INDEX")
  end, { buffer = bufnr, desc = "Diff This (Agent Diff)" })
  vim.keymap.set("n", "<leader>ghD", function()
    require("agent_diff").open_side("~")
  end, { buffer = bufnr, desc = "Diff This ~ (Agent Diff)" })
end

return M
