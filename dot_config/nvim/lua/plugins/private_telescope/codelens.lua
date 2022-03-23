local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local conf = require('telescope.config').values
local entry_display = require('telescope.pickers.entry_display')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local strings = require('plenary.strings')
local utils = require('telescope.utils')

local attach_mappings = function(prompt_bufnr)
  actions.select_default:replace(function()
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    vim.lsp.buf.execute_command(selection.value)
  end)

  return true
end

local build_displayer = function(widths)
  return entry_display.create({
    separator = " ",
    items = {
      { width = widths.idx + 1 }, -- +1 for ":" suffix
      { width = widths.title },
      { width = widths.command },
    },
  })
end

local build_make_display = function(displayer)
  return function(entry)
    return displayer({
      { entry.value.idx .. ":", "TelescopePromptPrefix" },
      { entry.value.title },
      { entry.value.command, "TelescopeResultsComment" },
    })
  end
end

local build_widths = function(results)
  local widths = {
    idx = 0,
    title = 0,
    command = 0,
  }

  for _, result in ipairs(results) do
    for key, value in pairs(widths) do
      widths[key] = math.max(value, strings.strdisplaywidth(result[key]))
    end
  end

  return widths
end

local build_entry_maker = function(results)
  local widths = build_widths(results)
  local displayer = build_displayer(widths)
  local make_display = build_make_display(displayer)
  return function(entry)
    return {
      value = entry,
      ordinal = entry.idx .. entry.title,
      display = make_display
    }
  end
end

local build_results = function()
  local lsp_results = vim.lsp.codelens.get()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local idx = 1
  local results = {}

  for _, result in ipairs(lsp_results) do
    local command = result.command
    local line = result.range.start.line
    if command and line == lnum - 1 then
      local entry = {
        idx = idx,
        title = result.command.title:gsub("\r\n", "\\r\\n"):gsub("\n", "\\n"):gsub("▶︎ ",""),
        command = command.command,
        arguments = command.arguments
      }

      table.insert(results, entry)
      idx = idx + 1
    end
  end

  return results
end

return function(opts)
  local results = build_results()

  if #results == 0 then
    return utils.notify("lsp_codelens", {
      msg = "No results from codelens",
      level = "INFO",
    })
  end

  pickers.new(opts, {
    prompt_title = "LSP CodeLens Actions",
    finder = finders.new_table({
      results = results,
      entry_maker = build_entry_maker(results)
    }),
    attach_mappings = attach_mappings,
    sorter = conf.generic_sorter(opts),
  }):find()
end

