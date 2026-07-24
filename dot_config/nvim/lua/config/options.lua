vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.g.lazyvim_picker = "snacks"

vim.g.lazyvim_ts_lsp = "tsgo"

vim.g.lazyvim_php_lsp = "intelephense"

vim.g.root_spec = { { ".git", "lua" }, "cwd" }

vim.g.snacks_animate = false

local node22 = vim.fn.trim(vim.fn.system("volta run --node 22 which node"))
local nodeBin = node22:gsub("/node$", "")

local newPath = [[let $PATH = ']] .. nodeBin .. [[:' . $PATH]]
vim.cmd(newPath)

vim.g.node_host_prog = vim.fn.trim(vim.fn.system("volta which neovim-node-host"))

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
