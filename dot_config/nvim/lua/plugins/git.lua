return {
  {
    "YouSame2/inlinediff-nvim",
    cmd = "InlineDiff",
    keys = {
      {
        "<leader>ghi",
        function()
          require("inlinediff").toggle()
        end,
        desc = "Toggle Inline Diff",
      },
    },
    opts = function()
      local colors = require("catppuccin.palettes").get_palette()
      local blend = require("catppuccin.utils.colors").blend

      return {
        colors = {
          InlineDiffAddContext = blend(colors.green, colors.base, 0.12),
          InlineDiffAddChange = blend(colors.green, colors.base, 0.28),
          InlineDiffDeleteContext = blend(colors.red, colors.base, 0.12),
          InlineDiffDeleteChange = blend(colors.red, colors.base, 0.28),
        },
      }
    end,
  },
}
