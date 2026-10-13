local M = {}

local contexts = {}

local function notify(message, level)
  vim.notify(message, level, { title = "Feedback" })
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
  local bufnr = vim.api.nvim_get_current_buf()
  local context = contexts[bufnr]
  if context and not require("agent_review.context").for_buffer(bufnr).closed then return context end
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

local function open_comments(context)
  local comments = {}
  for _, annotation in ipairs(require("agent_review").annotation.list()) do
    local path = annotation.target.file
    if annotation.root and path:sub(1, 1) ~= "/" then
      path = annotation.root .. "/" .. path
    end
    if normalized_absolute(path) == context.metadata.sourcePath
      and annotation.status ~= "resolved" and annotation.freshness ~= "stale" then
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

local function prompt(metadata, comments)
  local lines = {
    "# Feedback on your selected response", "",
    "I added line-specific feedback to this assistant response. Address each comment below.",
    "Assistant response ID: `" .. metadata.assistantMessageId .. "`",
  }
  for _, comment in ipairs(comments) do
    local first = "L" .. comment.startLine .. (comment.startCol and ":C" .. comment.startCol or "")
    local last = "L" .. comment.endLine .. (comment.endCol and ":C" .. comment.endCol or "")
    vim.list_extend(lines, { "", "## " .. comment.id .. ": " .. (first == last and first or first .. "-" .. last) })
    if #comment.quotedText > 0 then
      lines[#lines + 1] = ""
      for _, line in ipairs(comment.quotedText) do lines[#lines + 1] = "> " .. line end
    end
    vim.list_extend(lines, { "", comment.body })
  end
  return table.concat(lines, "\n") .. "\n\n"
end

local function quit(context)
  if context and context.metadata.reader then
    return require("agent_review.feedback_reader").close_view()
  end
  vim.schedule(function() vim.cmd("qa!") end)
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

  if context.submitting then return false end
  local comments = open_comments(context)
  if #comments == 0 then
    notify("Add at least one annotation before submitting", vim.log.levels.WARN)
    return false
  end

  local metadata = context.metadata
  local saved, save_err = require("agent_review.persistence").save_now()
  if not saved then
    if not metadata.reader then pcall(vim.fn.delete, metadata.feedbackPath) end
    notify(save_err, vim.log.levels.ERROR)
    return false
  end

  if metadata.reader then
    -- Capture the actual view before Agent Bridge can open a target picker.
    -- Its callback must not close a different conversation or a code tab.
    local view = require("agent_review.feedback_reader").for_buffer(vim.api.nvim_get_current_buf())
    if not view then return false end
    context.submitting = true
    local called, accepted = pcall(function()
      return require("agent_bridge").send(prompt(metadata, comments), {
        submit = false,
        switch_to_target = true,
      }, function(staged)
        context.submitting = false
        if not staged then return end
        context.disposition = "submit"
        if opts.quit ~= false then view.close_view() end
      end)
    end)
    if not called then
      context.submitting = false
      notify("Failed to stage feedback: " .. tostring(accepted), vim.log.levels.ERROR)
      return false
    end
    if not accepted then context.submitting = false end
    return accepted
  end

  -- Legacy standalone feedback still returns its payload through this file.
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

  context.disposition = "submit"
  if opts.quit ~= false then quit(context) end
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
  if opts.quit ~= false then
    quit(context)
  end
  return true
end

function M.discard(opts)
  opts = opts or {}
  local context = current_context()
  if not context then return false end
  if context then
    if context.metadata.reader then
      local reader = require("agent_review.feedback_reader")
      require("agent_review.render").clear_all()
      require("agent_review.state").replace({})
      local saved, err = require("agent_review.persistence").save_now()
      if not saved then
        notify(err, vim.log.levels.ERROR)
        return false
      end
      vim.fn.delete(context.metadata.feedbackPath)
      reader.set_notice("Discarded this message's feedback")
    else
      require("agent_review.context").release(require("agent_review.context").for_buffer())
      remove_feedback_directory(context)
    end
    context.disposition = "discard"
  end
  if opts.quit == true or (opts.quit ~= false and not (context and context.metadata.reader)) then
    quit(context)
  end
  return true
end

M.cancel = M.discard

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

  local store, err = require("agent_review.context").attach(bufnr, metadata)
  if not store then
    notify(err, vim.log.levels.ERROR)
    return false
  end
  contexts[bufnr] = { metadata = metadata, metadata_path = metadata_path }
  vim.b[bufnr].pi_feedback_disable_lint = true
  vim.diagnostic.enable(false, { bufnr = bufnr })
  vim.diagnostic.reset(nil, bufnr)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
  end

  local target = require("agent_review.target").context_for_buffer(bufnr)
  local workspace = require("agent_review.scope").key(target.root, target.path)
  if not store.sessions.current(workspace) then
    store.sessions.create({ name = "Pi feedback " .. metadata.assistantMessageId:sub(1, 8),
      workspace = workspace, root = target.root, file = target.root and nil or target.path })
  end

  local map_opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "<leader>rs", M.submit, vim.tbl_extend("force", map_opts, { desc = "Submit feedback" }))
  vim.keymap.set("n", "<leader>rk", M.keep, vim.tbl_extend("force", map_opts, { desc = "Keep feedback draft" }))
  vim.keymap.set("n", "<leader>rq", M.discard, vim.tbl_extend("force", map_opts, { desc = "Discard feedback" }))
  if not metadata.reader then
    vim.keymap.set("n", "q", M.discard, vim.tbl_extend("force", map_opts, { desc = "Discard feedback" }))
  end
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
      if context and not context.metadata.reader and context.disposition ~= "keep" and context.disposition ~= "submit" then
        remove_feedback_directory(context)
      end
    end,
  })

  require("agent_review.render").refresh_buffer(bufnr)
  return true
end

return M
