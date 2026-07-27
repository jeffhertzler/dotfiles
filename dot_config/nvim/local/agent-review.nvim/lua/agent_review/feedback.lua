local M = {}

local contexts = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Feedback" })
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "failed to read feedback metadata: " .. tostring(lines)
  end
  local decoded_ok, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok or type(value) ~= "table" then
    return nil, "failed to decode feedback metadata"
  end
  return value
end

local function normalized_absolute(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function validate_metadata(metadata, bufnr, metadata_path)
  if type(metadata.feedbackDirectory) ~= "string" or metadata.feedbackDirectory == "" then
    return nil, "feedback metadata is missing feedbackDirectory"
  end
  if type(metadata.sourcePath) ~= "string" or metadata.sourcePath == "" then
    return nil, "feedback metadata is missing sourcePath"
  end
  if type(metadata.feedbackPath) ~= "string" or metadata.feedbackPath == "" then
    return nil, "feedback metadata is missing feedbackPath"
  end
  if type(metadata.assistantMessageId) ~= "string" or metadata.assistantMessageId == "" then
    return nil, "feedback metadata is missing assistantMessageId"
  end

  local feedback_directory = normalized_absolute(metadata.feedbackDirectory)
  local expected = normalized_absolute(metadata.sourcePath)
  local feedback_path = normalized_absolute(metadata.feedbackPath)
  local normalized_metadata_path = normalized_absolute(metadata_path)
  local actual = normalized_absolute(vim.api.nvim_buf_get_name(bufnr))
  if expected ~= actual then
    return nil, "feedback metadata does not match the current buffer"
  end
  if vim.fs.dirname(expected) ~= feedback_directory
    or vim.fs.dirname(feedback_path) ~= feedback_directory
    or vim.fs.dirname(normalized_metadata_path) ~= feedback_directory then
    return nil, "feedback artifacts must share one directory"
  end
  metadata.feedbackDirectory = feedback_directory
  metadata.sourcePath = expected
  metadata.feedbackPath = feedback_path
  return metadata
end

local function current_context()
  return contexts[vim.api.nvim_get_current_buf()]
end

local function comment_payload(annotation)
  local target = annotation.target
  return {
    id = annotation.id,
    body = annotation.body,
    kind = annotation.kind,
    status = annotation.status,
    freshness = annotation.freshness,
    startLine = target.start_line,
    startCol = target.start_col,
    endLine = target.end_line,
    endCol = target.end_col,
    selection = target.selection,
    columnEncoding = target.column_encoding,
    quotedText = vim.deepcopy(annotation.anchor and annotation.anchor.selected or {}),
  }
end

local function open_comments()
  local comments = {}
  for _, annotation in ipairs(require("agent_review").annotation.list()) do
    if annotation.status ~= "resolved" and annotation.freshness ~= "stale" then
      table.insert(comments, comment_payload(annotation))
    end
  end
  table.sort(comments, function(first, second)
    if first.startLine ~= second.startLine then
      return first.startLine < second.startLine
    end
    return first.id < second.id
  end)
  for index, comment in ipairs(comments) do
    comment.id = string.format("feedback-%d", index)
  end
  return comments
end

local function write_json_atomically(path, value)
  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then
    return false, "failed to encode feedback: " .. tostring(encoded)
  end

  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  local temporary = string.format("%s.tmp.%d", path, vim.fn.getpid())
  local write_ok, write_result = pcall(vim.fn.writefile, { encoded }, temporary, "b")
  if not write_ok or write_result ~= 0 then
    pcall(vim.fn.delete, temporary)
    return false, "failed to write feedback"
  end
  vim.fn.setfperm(temporary, "rw-------")

  local renamed, rename_error = vim.uv.fs_rename(temporary, path)
  if not renamed then
    pcall(vim.fn.delete, temporary)
    return false, "failed to replace feedback: " .. tostring(rename_error)
  end
  vim.fn.setfperm(path, "rw-------")
  return true
end

local function quit()
  vim.schedule(function()
    vim.cmd("qa!")
  end)
end

local function remove_feedback_directory(context)
  if context and context.metadata and context.metadata.feedbackDirectory then
    pcall(vim.fn.delete, context.metadata.feedbackDirectory, "rf")
  end
end

function M.submit(opts)
  opts = opts or {}
  local context = current_context()
  if not context then
    notify("The current buffer is not Pi feedback", vim.log.levels.WARN)
    return false
  end

  local comments = open_comments()
  if #comments == 0 then
    notify("Add at least one annotation before submitting", vim.log.levels.WARN)
    return false
  end

  local metadata = context.metadata
  local ok, err = write_json_atomically(metadata.feedbackPath, {
    schemaVersion = 1,
    piSessionId = metadata.piSessionId,
    assistantMessageId = metadata.assistantMessageId,
    sourcePath = metadata.sourcePath,
    submittedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    comments = comments,
  })
  if not ok then
    notify(err, vim.log.levels.ERROR)
    return false
  end

  local saved, save_err = require("agent_review.persistence").save_now()
  if not saved then
    pcall(vim.fn.delete, metadata.feedbackPath)
    notify(save_err, vim.log.levels.ERROR)
    return false
  end

  context.disposition = "submit"
  notify(string.format("Submitted %d feedback comment%s", #comments, #comments == 1 and "" or "s"))
  if opts.quit ~= false then
    quit()
  end
  return true
end

function M.keep(opts)
  opts = opts or {}
  local context = current_context()
  if not context then
    notify("The current buffer is not Pi feedback", vim.log.levels.WARN)
    return false
  end
  local saved, save_err = require("agent_review.persistence").save_now()
  if not saved then
    notify(save_err, vim.log.levels.ERROR)
    return false
  end
  context.disposition = "keep"
  notify("Kept feedback draft")
  if opts.quit ~= false then
    quit()
  end
  return true
end

function M.discard(opts)
  opts = opts or {}
  local context = current_context()
  if context then
    context.disposition = "discard"
    remove_feedback_directory(context)
  end
  if opts.quit ~= false then
    quit()
  end
  return true
end

M.cancel = M.discard

local function show_help()
  notify("<leader>ra annotate · visual <leader>ra range · <leader>rc clear · <leader>rk keep · <leader>rs submit · q discard")
end

function M.attach(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local metadata_path = opts.metadata_path or vim.env.PI_FEEDBACK_METADATA
  if not metadata_path or metadata_path == "" then
    notify("PI_FEEDBACK_METADATA is unavailable", vim.log.levels.ERROR)
    return false
  end

  local metadata, read_err = read_json(metadata_path)
  if not metadata then
    notify(read_err, vim.log.levels.ERROR)
    return false
  end
  metadata, read_err = validate_metadata(metadata, bufnr, metadata_path)
  if not metadata then
    notify(read_err, vim.log.levels.ERROR)
    return false
  end

  contexts[bufnr] = { metadata = metadata, metadata_path = metadata_path }
  vim.b[bufnr].pi_feedback = vim.deepcopy(metadata)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  local review = require("agent_review")
  if not review.session.current() then
    local short_id = metadata.assistantMessageId:sub(1, 8)
    review.session.create("Pi feedback " .. short_id)
  end

  local map_opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "<leader>rs", M.submit, vim.tbl_extend("force", map_opts, { desc = "Submit feedback" }))
  vim.keymap.set("n", "<leader>rk", M.keep, vim.tbl_extend("force", map_opts, { desc = "Keep feedback draft" }))
  vim.keymap.set("n", "<leader>rq", M.discard, vim.tbl_extend("force", map_opts, { desc = "Discard feedback" }))
  vim.keymap.set("n", "q", M.discard, vim.tbl_extend("force", map_opts, { desc = "Discard feedback" }))
  vim.keymap.set("n", "?", show_help, vim.tbl_extend("force", map_opts, { desc = "Feedback controls" }))
  vim.api.nvim_buf_create_user_command(bufnr, "AgentFeedbackSubmit", function()
    M.submit()
  end, { desc = "Submit Pi feedback annotations" })
  vim.api.nvim_buf_create_user_command(bufnr, "AgentFeedbackKeep", function()
    M.keep()
  end, { desc = "Keep Pi feedback draft" })
  vim.api.nvim_buf_create_user_command(bufnr, "AgentFeedbackDiscard", function()
    M.discard()
  end, { desc = "Discard Pi feedback" })

  local group = vim.api.nvim_create_augroup("AgentFeedback" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    once = true,
    callback = function()
      local context = contexts[bufnr]
      if context and context.disposition ~= "keep" and context.disposition ~= "submit" then
        remove_feedback_directory(context)
      end
    end,
  })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  review.refresh()
  show_help()
  return true
end

return M
