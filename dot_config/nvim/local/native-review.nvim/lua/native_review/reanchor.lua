local M = {}

local target_util = require("native_review.target")

local function lines_equal(first, second)
  if type(first) ~= "table" or type(second) ~= "table" or #first ~= #second then
    return false
  end
  for index, line in ipairs(first) do
    if line ~= second[index] then
      return false
    end
  end
  return true
end

local function valid_saved_target(bufnr, target)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if target.start_line < 1 or target.end_line > line_count then
    return false
  end
  if target.start_col then
    local first = vim.api.nvim_buf_get_lines(bufnr, target.start_line - 1, target.start_line, false)[1] or ""
    local last = vim.api.nvim_buf_get_lines(bufnr, target.end_line - 1, target.end_line, false)[1] or ""
    if target.start_col > #first + 1 or target.end_col > #last + 1 then
      return false
    end
  end
  return true
end

local function exact_match(bufnr, annotation)
  if not valid_saved_target(bufnr, annotation.target) then
    return false
  end
  local current = target_util.anchor_for_buffer(bufnr, annotation.target)
  return current and lines_equal(current.selected, annotation.anchor.selected)
end

local function line_candidates(lines, selected)
  local candidates = {}
  if #selected == 0 or #selected > #lines then
    return candidates
  end

  for start_line = 1, #lines - #selected + 1 do
    local matches = true
    for offset, expected in ipairs(selected) do
      if lines[start_line + offset - 1] ~= expected then
        matches = false
        break
      end
    end
    if matches then
      table.insert(candidates, {
        start_line = start_line,
        end_line = start_line + #selected - 1,
        selection = "line",
      })
    end
  end
  return candidates
end

local function single_line_character_candidates(bufnr, lines, selected)
  local candidates = {}
  local needle = selected[1]
  if needle == "" then
    return candidates
  end

  for line_number, line in ipairs(lines) do
    local offset = 1
    while offset <= #line do
      local start_byte, end_byte = line:find(needle, offset, true)
      if not start_byte then
        break
      end
      table.insert(candidates, {
        start_line = line_number,
        start_col = start_byte,
        end_line = line_number,
        end_col = target_util.previous_char_col(bufnr, line_number - 1, end_byte),
        selection = "character",
      })
      offset = math.max(start_byte + 1, end_byte + 1)
    end
  end
  return candidates
end

local function multi_line_character_candidates(bufnr, lines, selected)
  local candidates = {}
  local count = #selected
  if count < 2 or count > #lines then
    return candidates
  end

  local first_selected = selected[1]
  local last_selected = selected[count]
  for start_line = 1, #lines - count + 1 do
    local first_line = lines[start_line]
    local first_matches = first_selected == ""
      or (#first_selected <= #first_line and first_line:sub(#first_line - #first_selected + 1) == first_selected)
    if first_matches then
      local matches = true
      for offset = 2, count - 1 do
        if lines[start_line + offset - 1] ~= selected[offset] then
          matches = false
          break
        end
      end
      local last_line = lines[start_line + count - 1]
      if matches and last_line:sub(1, #last_selected) == last_selected then
        local start_col = #first_line - #first_selected + 1
        local end_col = target_util.previous_char_col(bufnr, start_line + count - 2, #last_selected)
        table.insert(candidates, {
          start_line = start_line,
          start_col = math.max(1, start_col),
          end_line = start_line + count - 1,
          end_col = end_col,
          selection = "character",
        })
      end
    end
  end
  return candidates
end

local function context_score(lines, candidate, anchor)
  local score = 0
  local before = anchor.before or {}
  local after = anchor.after or {}

  for offset = 1, math.min(#before, candidate.start_line - 1) do
    if lines[candidate.start_line - offset] == before[#before - offset + 1] then
      score = score + 1
    end
  end
  for offset = 1, math.min(#after, #lines - candidate.end_line) do
    if lines[candidate.end_line + offset] == after[offset] then
      score = score + 1
    end
  end
  return score
end

local function unique_best(lines, candidates, anchor)
  if #candidates == 1 then
    return candidates[1]
  end
  local best, best_score, tied = nil, -1, false
  for _, candidate in ipairs(candidates) do
    local score = context_score(lines, candidate, anchor)
    if score > best_score then
      best = candidate
      best_score = score
      tied = false
    elseif score == best_score then
      tied = true
    end
  end
  if tied or best_score <= 0 then
    return nil
  end
  return best
end

local function same_target(first, second)
  return first.start_line == second.start_line
    and first.start_col == second.start_col
    and first.end_line == second.end_line
    and first.end_col == second.end_col
end

function M.resolve(bufnr, annotation)
  local anchor = annotation.anchor
  if type(anchor) ~= "table" or type(anchor.selected) ~= "table" or #anchor.selected == 0 then
    return "fresh", nil
  end
  if exact_match(bufnr, annotation) then
    return "fresh", nil
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local candidates
  if annotation.target.selection == "character" then
    if #anchor.selected == 1 then
      candidates = single_line_character_candidates(bufnr, lines, anchor.selected)
    else
      candidates = multi_line_character_candidates(bufnr, lines, anchor.selected)
    end
  else
    candidates = line_candidates(lines, anchor.selected)
  end

  local candidate = unique_best(lines, candidates, anchor)
  if not candidate then
    return "stale", nil
  end

  candidate.file = annotation.target.file
  candidate.side = annotation.target.side
  candidate.column_encoding = annotation.target.column_encoding
  if same_target(annotation.target, candidate) then
    return "fresh", nil
  end
  return "reanchored", candidate
end

return M
