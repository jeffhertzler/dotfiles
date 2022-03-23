local M = {}

function M.dark()
  vim.opt.background = "dark"
end

function M.light()
  vim.opt.background = "light"
end

function M.toggle()
  if vim.opt.background == "light" then
    M.dark()
  else
    M.light()
  end
end

return M

