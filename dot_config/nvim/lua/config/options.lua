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

local node_launcher = vim.fn.exepath("neovim-node-host")
if node_launcher ~= "" then
  local node_hosts = {
    vim.fs.joinpath(vim.fs.dirname(node_launcher), "..", "neovim", "bin", "cli.js"),
    vim.uv.fs_realpath(node_launcher),
  }
  for _, node_host in ipairs(node_hosts) do
    if node_host and vim.fn.filereadable(node_host) == 1 then
      vim.g.node_host_prog = vim.uv.fs_realpath(node_host) or node_host
      break
    end
  end
end

local python_host = vim.fn.exepath(vim.fn.has("win32") == 1 and "pynvim-python.exe" or "pynvim-python")
if python_host ~= "" then
  vim.g.python3_host_prog = python_host
end

vim.opt.relativenumber = false
vim.opt.showtabline = 0
vim.opt.swapfile = false

local function has_env(name)
  local value = vim.env[name]
  return value ~= nil and value ~= ""
end

local in_herdr = vim.env.HERDR_ENV == "1"
local direct_ssh = has_env("SSH_TTY") and not has_env("TMUX") and not in_herdr

if direct_ssh then
  vim.g.clipboard = "osc52"
end

vim.opt.clipboard = { "unnamed", "unnamedplus" }

if in_herdr and vim.fn.has("clipboard") == 0 then
  -- Herdr forwards OSC 52 writes but does not support reads. Keep paste backed
  -- by Neovim's registers and only mirror explicit yank operations outward.
  vim.opt.clipboard = {}
  local osc52_copy = require("vim.ui.clipboard.osc52").copy("+")

  vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Copy Herdr yanks to the client clipboard with OSC 52",
    callback = function()
      if vim.v.event.operator == "y" then
        osc52_copy(vim.v.event.regcontents)
      end
    end,
  })
end
