local pickers = require('telescope.pickers')
local action_state = require('telescope.actions.state')
local actions = require('telescope.actions')
local entry_display = require('telescope.pickers.entry_display')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local strings = require('plenary.strings')

return function(opts)
  opts = opts or {}

  local results_lsp = vim.lsp.codelens.get(0)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  if not results_lsp or vim.tbl_isempty(results_lsp) then
    print "No executable codelens actions found at the current buffer"
    return
  end

  local idx = 1
  local results = {}
  local widths = {
    idx = 0,
    command_title = 0,
    client_name = 0,
  }

  for _, result in ipairs(results_lsp) do
    if result.command and result.range.start.line == cursor_pos[1] - 1 then
      local entry = {
        idx = idx,
        command_title = result.command.title:gsub("\r\n", "\\r\\n"):gsub("\n", "\\n"):gsub("▶︎ ",""),
        command = result.command,
        client_name = result.command.command,
      }

      for key, value in pairs(widths) do
        widths[key] = math.max(value, strings.strdisplaywidth(entry[key]))
      end

      table.insert(results, entry)
      idx = idx + 1
    end
  end

  if #results == 0 then
    print "No codelens actions available"
    return
  end

  local displayer = entry_display.create {
    separator = " ",
    items = {
      { width = widths.idx + 1 }, -- +1 for ":" suffix
      { width = widths.command_title },
      { width = widths.client_name },
    },
  }

  local function make_display(entry)
    return displayer {
      { entry.idx .. ":", "TelescopePromptPrefix" },
      { entry.command_title },
      { entry.client_name, "TelescopeResultsComment" },
    }
  end

  local execute_action = opts.execute_action
    or function(action)
      if action.edit or type(action.command) == "table" then
        if action.edit then
          vim.lsp.util.apply_workspace_edit(action.edit)
        end
        if type(action.command) == "table" then
          vim.lsp.buf.execute_command(action.command)
        end
      else
        vim.lsp.buf.execute_command(action)
      end
    end

  pickers.new(opts, {
    prompt_title = "LSP CodeLens Actions",
    finder = finders.new_table {
      results = results,
      entry_maker = function(line)
        return {
          valid = line ~= nil,
          value = line.command,
          ordinal = line.idx .. line.command_title,
          command_title = line.command_title,
          idx = line.idx,
          client_name = line.client_name,
          display = make_display,
        }
      end,
    },
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        local action = selection.value

        execute_action(action)
      end)

      return true
    end,
    sorter = conf.generic_sorter(opts),
  }):find()
end

