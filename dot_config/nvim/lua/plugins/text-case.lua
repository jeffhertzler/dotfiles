return {
  "johmsalas/text-case.nvim",
  keys = {
    "ga",
  },
  cmd = {
    "S",
    "Subs",
    "TextCaseStartReplacingCommand",
  },
  config = function()
    require("textcase").setup({
      substitude_command_name = "S",
    })
  end,
  lazy = false,
}
