local M = {}

local function modules()
  return require("codediff.ui.highlights"), require("codediff.ui.inline"), require("codediff.ui.core")
end

function M.setup()
  local highlights = require("codediff.ui.highlights")
  highlights.setup()
end

function M.clear(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  local highlights, inline = modules()
  inline.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, highlights.ns_highlight, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, highlights.ns_filler, 0, -1)
end

function M.inline(session)
  local _, inline = modules()
  M.clear(session.modified_buf)
  inline.render_inline_diff(
    session.modified_buf,
    session.diff_result,
    session.original_lines,
    session.modified_lines,
    {
      -- Parsing thousands of virtual deletion lines can dominate the bounded C
      -- diff itself. When refinement times out, retain the line diff but skip
      -- syntax parsing for its virtual old text.
      filetype = session.diff_result.hit_timeout and "" or vim.bo[session.modified_buf].filetype,
    }
  )
end

function M.side_by_side(session)
  local _, _, core = modules()
  M.clear(session.original_buf)
  M.clear(session.modified_buf)
  core.render_diff(
    session.original_buf,
    session.modified_buf,
    session.original_lines,
    session.modified_lines,
    session.diff_result
  )

  for _, win in ipairs({ session.original_win, session.modified_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.wo[win].wrap = false
      vim.wo[win].scrollbind = true
      vim.wo[win].cursorbind = false
    end
  end
  if session.modified_win and vim.api.nvim_win_is_valid(session.modified_win) then
    vim.api.nvim_set_current_win(session.modified_win)
  end
  pcall(vim.cmd, "syncbind")
end

return M
