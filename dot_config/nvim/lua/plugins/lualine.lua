return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    opts.options.section_separators = { left = "", right = "" }
    table.insert(opts.sections.lualine_x, 1, {
      function()
        return require("agent_review").status.text()
      end,
      cond = function()
        return package.loaded["agent_review"] and require("agent_review").status.has()
      end,
      color = function()
        return { fg = Snacks.util.color("DiagnosticWarn") }
      end,
      on_click = function()
        require("agent_review").status.open()
      end,
    })
  end,
}
