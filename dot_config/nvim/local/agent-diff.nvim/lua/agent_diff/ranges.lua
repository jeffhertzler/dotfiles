local M = {}

local function byte_col(line, utf16_col)
  if utf16_col <= 1 then
    return 0
  end
  local ok, value = pcall(require("codediff.core.compat").str_byteindex_utf16, line, utf16_col - 1)
  return ok and value or (utf16_col - 1)
end

local function apply_range(bufnr, namespace, range, lines, rows, highlight, column_offset, priority)
  if not range then
    return
  end
  for line_number = range.start_line, range.end_line do
    local text = lines[line_number]
    local row = rows[line_number]
    if text and row then
      local start_col = line_number == range.start_line and byte_col(text, range.start_col) or 0
      local end_col = line_number == range.end_line and byte_col(text, range.end_col) or #text
      start_col = math.max(0, math.min(start_col, #text))
      end_col = math.max(start_col, math.min(end_col, #text))
      if end_col > start_col then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, row, start_col + column_offset, {
          end_col = end_col + column_offset,
          hl_group = highlight,
          priority = priority or 240,
        })
      end
    end
  end
end

function M.spans(result, side, line_number, lines)
  local spans = {}
  local text = lines[line_number] or ""
  for _, change in ipairs(result.changes or {}) do
    for _, inner in ipairs(change.inner_changes or {}) do
      local range = inner[side]
      if range and line_number >= range.start_line and line_number <= range.end_line then
        local start_col = line_number == range.start_line and byte_col(text, range.start_col) or 0
        local end_col = line_number == range.end_line and byte_col(text, range.end_col) or #text
        start_col = math.max(0, math.min(start_col, #text))
        end_col = math.max(start_col, math.min(end_col, #text))
        if end_col > start_col then
          table.insert(spans, { start_col, end_col })
        end
      end
    end
  end
  table.sort(spans, function(a, b)
    return a[1] < b[1]
  end)
  return spans
end

function M.chunks(text, spans, base_highlight, change_highlight)
  local chunks, cursor = {}, 0
  for _, span in ipairs(spans) do
    if span[1] > cursor then
      table.insert(chunks, { text:sub(cursor + 1, span[1]), base_highlight })
    end
    if span[2] > span[1] then
      table.insert(chunks, { text:sub(span[1] + 1, span[2]), change_highlight })
    end
    cursor = math.max(cursor, span[2])
  end
  if cursor < #text then
    table.insert(chunks, { text:sub(cursor + 1), base_highlight })
  end
  if #chunks == 0 then
    table.insert(chunks, { text, base_highlight })
  end
  table.insert(chunks, { string.rep(" ", 200), base_highlight })
  return chunks
end

function M.apply(bufnr, namespace, result, old, new, old_rows, new_rows, opts)
  opts = opts or {}
  for _, change in ipairs(result.changes or {}) do
    for _, inner in ipairs(change.inner_changes or {}) do
      apply_range(
        bufnr,
        namespace,
        inner.original,
        old,
        old_rows,
        opts.old_highlight or "CodeDiffCharDelete",
        opts.column_offset or 0,
        opts.priority
      )
      apply_range(
        bufnr,
        namespace,
        inner.modified,
        new,
        new_rows,
        opts.new_highlight or "CodeDiffCharInsert",
        opts.column_offset or 0,
        opts.priority
      )
    end
  end
end

return M
