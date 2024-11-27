return {
  "nvim-telescope/telescope.nvim",
  opts = function()
    local actions = require("telescope.actions")
    local open_with_trouble = function(...)
      return require("trouble.sources.telescope").open(...)
    end
    local find_files_ignore = function()
      local action_state = require("telescope.actions.state")
      local line = action_state.get_current_line()
      LazyVim.pick("find_files", { no_ignore = false, default_text = line })()
    end
    local find_files_no_ignore = function()
      local action_state = require("telescope.actions.state")
      local line = action_state.get_current_line()
      LazyVim.pick("find_files", { no_ignore = true, default_text = line })()
    end
    local find_files_with_hidden = function()
      local action_state = require("telescope.actions.state")
      local line = action_state.get_current_line()
      LazyVim.pick("find_files", { hidden = true, default_text = line })()
    end
    return {
      defaults = {
        mappings = {
          i = {
            ["<C-h>"] = actions.which_key,
            ["<C-n>"] = actions.cycle_history_next,
            ["<C-p>"] = actions.cycle_history_prev,
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-t>"] = open_with_trouble,
            ["<M-i>"] = find_files_no_ignore,
            ["<M-h>"] = find_files_with_hidden,
            ["<M-n>"] = find_files_ignore,
          },
          n = {
            ["<C-c>"] = actions.close,
          },
        },
      },
    }
  end,
}
