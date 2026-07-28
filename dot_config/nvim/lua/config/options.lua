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
  -- Native Neovim cannot execute npm's PowerShell shim, and Treesitter needs a
  -- native compiler. Keep these ahead of the Git Bash PATH inherited by Nvim.
  prepend_path("C:/Program Files/LLVM/bin")
  prepend_path(vim.fn.expand("$APPDATA/npm/node_modules/tree-sitter-cli"))

  local git_bash = "C:/Progra~1/Git/bin/bash.exe"
  if vim.fn.executable(git_bash) == 1 then
    vim.opt.shell = git_bash
    vim.opt.shellcmdflag = "-c"
    vim.opt.shellredir = ">%s 2>&1"
    vim.opt.shellpipe = "2>&1| tee"
    vim.opt.shellquote = ""
    vim.opt.shellxquote = ""
  end
elseif vim.fn.executable("volta") == 1 and vim.fn.executable("which") == 1 then
  -- Arch and macOS retain Volta's Node 22 for Node-backed editor tooling while
  -- project runtimes migrate incrementally. The Neovim host itself is managed
  -- by Mise and is discovered through Mise's ordinary PATH shim.
  local node22 = vim.fn.trim(vim.fn.system({ "volta", "run", "--node", "22", "which", "node" }))
  if vim.v.shell_error == 0 and vim.fn.executable(node22) == 1 then
    prepend_path(vim.fs.dirname(node22))
  end
end

local mise = vim.fn.exepath("mise")
if mise ~= "" then
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
