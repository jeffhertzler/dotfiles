local M = {}

local function location(target)
  if target.start_col then
    return string.format(
      "%s:L%d:C%d-L%d:C%d",
      target.file,
      target.start_line,
      target.start_col,
      target.end_line,
      target.end_col
    )
  end
  return string.format("@%s#L%d-%d", target.file, target.start_line, target.end_line)
end

local function sorted_annotations(annotations, opts)
  local result = {}
  for _, annotation in ipairs(annotations) do
    local include_status = opts.include_resolved or annotation.status ~= "resolved"
    local include_freshness = opts.include_stale or annotation.freshness ~= "stale"
    if include_status and include_freshness then
      table.insert(result, annotation)
    end
  end
  table.sort(result, function(first, second)
    local first_key = table.concat({ first.root or "", first.target.file, first.target.side, string.format("%09d", first.target.start_line), first.id }, "\0")
    local second_key = table.concat({ second.root or "", second.target.file, second.target.side, string.format("%09d", second.target.start_line), second.id }, "\0")
    return first_key < second_key
  end)
  return result
end

local function append_anchor(out, annotation)
  if annotation.target.side == "working" then
    return
  end
  local selected = annotation.anchor and annotation.anchor.selected or nil
  if not selected or #selected == 0 then
    return
  end

  table.insert(out, "- Anchored text:")
  for _, line in ipairs(selected) do
    table.insert(out, "  > " .. line)
  end
end

function M.build(annotations, opts)
  opts = opts or {}
  local selected = sorted_annotations(annotations or {}, opts)
  if #selected == 0 then
    return nil, "no fresh open review annotations"
  end

  local out = {
    "# Agent Review annotations",
    "",
    "Address each open annotation below. Keep the annotation IDs in your response so the review state can be updated later.",
    "Targets use one-based lines and UTF-8 byte columns. Old/new targets may refer to a non-working revision.",
    "",
    "Schema: `agent-review/v1`",
    "Neovim RPC server: `" .. (vim.v.servername ~= "" and vim.v.servername or "unavailable") .. "`",
    "Use the `agent-review` CLI; run `agent-review context` before making review-state changes.",
    "Import findings with `agent-review apply --stdin`; payloads use `{ schemaVersion = 1, comments = { ... } }`.",
    "After editing files, run `agent-review refresh`, then `agent-review resolve ID...` for addressed comments.",
  }

  for _, annotation in ipairs(selected) do
    local revision = annotation.revision and annotation.revision.selected_expression or "WORKING"
    table.insert(out, "")
    table.insert(out, string.format("## %s — %s", annotation.id, string.upper(annotation.target.side)))
    table.insert(out, "")
    if annotation.root then
      table.insert(out, "- Repository: `" .. annotation.root .. "`")
    end
    if annotation.session_id then
      table.insert(out, "- Session: `" .. annotation.session_id .. "`")
    end
    table.insert(out, "- Target: `" .. location(annotation.target) .. "`")
    table.insert(out, "- Revision: `" .. tostring(revision or "WORKING") .. "`")
    table.insert(out, "- Kind: `" .. (annotation.kind or "note") .. "`")
    table.insert(out, "- Status: `" .. (annotation.status or "open") .. "`")
    table.insert(out, "- Freshness: `" .. (annotation.freshness or "fresh") .. "`")
    append_anchor(out, annotation)
    table.insert(out, "")
    table.insert(out, "### Comment")
    table.insert(out, "")
    table.insert(out, annotation.body)
  end

  return table.concat(out, "\n")
end

return M
