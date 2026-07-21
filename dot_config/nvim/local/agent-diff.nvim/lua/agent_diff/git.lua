local M = {}

local function split_lines(text)
  if text == "" then
    return {}
  end
  local lines = vim.split(text, "\n", { plain = true })
  if text:sub(-1) == "\n" then
    table.remove(lines)
  end
  return lines
end

local function relative_path(root, path)
  local relative = vim.fs.relpath(root, path)
  if relative then
    return relative
  end
  return path:sub(#root + 2)
end

function M.context(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.bo[bufnr].buftype ~= "" then
    return nil, "Agent Diff requires a regular file buffer"
  end
  local path = vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
  local root = vim.fs.root(path, ".git")
  if not root then
    return nil, "File is not inside a Git repository"
  end
  root = vim.fs.normalize(root)
  return {
    root = root,
    path = path,
    relative_path = relative_path(root, path),
  }
end

function M.load_revision(root, relative_path, revision, callback)
  if revision == "WORKING" then
    local path = root .. "/" .. relative_path
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      callback(nil, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), bufnr)
    elseif vim.uv.fs_stat(path) then
      callback(nil, vim.fn.readfile(path), nil)
    else
      callback(nil, {}, nil)
    end
    return
  end

  local object = revision == "INDEX" and (":" .. relative_path) or (revision .. ":" .. relative_path)
  vim.system({ "git", "show", object }, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        callback(nil, split_lines(result.stdout or ""), nil)
      elseif revision == "INDEX" then
        callback(nil, {}, nil)
      else
        vim.system({ "git", "rev-parse", "--verify", revision .. "^{commit}" }, { cwd = root, text = true }, function(verify)
          vim.schedule(function()
            if verify.code == 0 then
              callback(nil, {}, nil)
            else
              callback(vim.trim(result.stderr or ("Could not read " .. object)))
            end
          end)
        end)
      end
    end)
  end)
end

function M.load(context, revision, callback)
  M.load_revision(context.root, context.relative_path, revision or "HEAD", callback)
end

return M
