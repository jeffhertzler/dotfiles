local copy = function()
  if vim.v.event.operator == 'y' and vim.v.event.regname == '' then
    require('osc52').copy_register('+')
  end
end

local configGroup = vim.api.nvim_create_augroup("MyConfig", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = copy,
  group = configGroup,
})
vim.api.nvim_create_autocmd("TextYankPost", {
  command = [[silent! lua vim.highlight.on_yank()]],
  group = configGroup,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "handlebars",
  command = [[setlocal commentstring={{!--\ %s\ --}}]],
  group = configGroup,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "php",
  command = [[setlocal commentstring=//\ %s]],
  group = configGroup,
})
vim.api.nvim_create_autocmd({ "BufWritePre", "FileWritePre" }, {
  callback = function()
    if vim.tbl_contains({ 'oil' }, vim.bo.ft) then
      return
    end
    local dir = vim.fn.expand('<afile>:p:h')
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end,
  group = configGroup,
})
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    package.loaded["feline"] = nil
    package.loaded["catppuccin.groups.integrations.feline"] = nil
    require("feline").setup {
      components = require("catppuccin.groups.integrations.feline").get(),
    }
  end,
})
