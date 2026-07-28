vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.g.lazyvim_picker = "snacks"

vim.g.lazyvim_ts_lsp = "tsgo"

vim.g.lazyvim_php_lsp = "intelephense"

vim.g.root_spec = { { ".git", "lua" }, "cwd" }

vim.g.snacks_animate = false

local path_separator = vim.fn.has("win32") == 1 and ";" or ":"

local function prepend_path(path)
  if path and path ~= "" and vim.fn.isdirectory(path) == 1 then
    vim.env.PATH = path .. path_separator .. (vim.env.PATH or "")
  end
end

if vim.fn.has("win32") == 1 then
  -- Tree-sitter needs a native compiler even when Nvim is launched outside
  -- Git Bash, whose startup config already exposes LLVM.
  prepend_path("C:/Program Files/LLVM/bin")

  local git_bash = "C:/Progra~1/Git/bin/bash.exe"
  if vim.fn.executable(git_bash) == 1 then
    vim.opt.shell = git_bash
    vim.opt.shellcmdflag = "-c"
    vim.opt.shellredir = ">%s 2>&1"
    vim.opt.shellpipe = "2>&1| tee"
    vim.opt.shellquote = ""
    vim.opt.shellxquote = ""
  end
end

local mise = vim.fn.exepath("mise")
if mise ~= "" then
  if vim.fn.has("win32") ~= 1 then
    local node = vim.fn.trim(vim.fn.system({ mise, "which", "node" }))
    if vim.v.shell_error == 0 and vim.fn.executable(node) == 1 then
      prepend_path(vim.fs.dirname(node))
    end
  end

  local neovim_package = vim.fn.trim(vim.fn.system({ mise, "where", "npm:neovim" }))
  local node_hosts = {
    vim.fs.joinpath(neovim_package, "node_modules", "neovim", "bin", "cli.js"),
    vim.fs.joinpath(neovim_package, "lib", "node_modules", "neovim", "bin", "cli.js"),
  }
  for _, node_host in ipairs(node_hosts) do
    if vim.v.shell_error == 0 and vim.fn.filereadable(node_host) == 1 then
      vim.g.node_host_prog = node_host
      break
    end
  end
end

vim.opt.relativenumber = false
vim.opt.showtabline = 0
vim.opt.swapfile = false

if vim.env.HERDR_ENV == "1" then
  local osc52_copy = require("vim.ui.clipboard.osc52").copy("+")
  local clipboard_cache = { {}, "v" }

  local function copy(lines, regtype)
    clipboard_cache = { vim.deepcopy(lines), regtype }
    osc52_copy(lines)
  end

  local function paste()
    return vim.deepcopy(clipboard_cache)
  end

  vim.g.clipboard = {
    name = "Herdr OSC 52",
    copy = { ["+"] = copy, ["*"] = copy },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end

vim.opt.clipboard = { "unnamed", "unnamedplus" }
