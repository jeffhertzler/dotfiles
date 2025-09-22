return {
  {
    "stevearc/oil.nvim",
    dependencies = { { "nvim-mini/mini.icons", opts = {} } },
    lazy = false,
    keys = {
      {
        "-",
        "<cmd>Oil<cr>",
        desc = "Open parent directory",
      },
    },
    config = function()
      local columns = { "icon" }
      local oil = require("oil")
      oil.setup({
        keymaps = {
          ["<C-h>"] = false,
          ["<C-l>"] = false,
          ["<C-t>"] = false,
          ["RR"] = "actions.refresh",
          ["<C-A-j>"] = "actions.select_split",
          ["<C-A-l>"] = "actions.select_vsplit",
          ["<leader>uP"] = function()
            if #columns == 1 then
              columns = { "icon", "permissions", "size", "mtime" }
            else
              columns = { "icon" }
            end
            oil.set_columns(columns)
          end,
        },
        lsp_file_methods = {
          autosave_changes = "unmodified",
        },
        skip_confirm_for_simple_edits = true,
        watch_for_changes = true,
        view_options = {
          show_hidden = true,
        },
      })

      local LazyRoot = require("lazyvim.util.root")

      ---@param patterns string[]|string
      function LazyRoot.detectors.pattern(buf, patterns)
        patterns = type(patterns) == "string" and { patterns } or patterns
        local path = LazyRoot.bufpath(buf) or vim.uv.cwd()
        if vim.bo[buf].filetype == "oil" then
          path = path:gsub("^oil:", "")
        end
        local pattern = vim.fs.find(function(name)
          for _, p in ipairs(patterns) do
            if name == p then
              return true
            end
            if p:sub(1, 1) == "*" and name:find(vim.pesc(p:sub(2)) .. "$") then
              return true
            end
          end
          return false
        end, { path = path, upward = true })[1]
        return pattern and { vim.fs.dirname(pattern) } or {}
      end
    end,
  },
  {
    "stevearc/quicker.nvim",
    event = "FileType qf",
    ---@module "quicker"
    ---@type quicker.SetupOptions
    opts = {},
  },
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        main = {
          file = false,
        },
      },
    },
  },
}
