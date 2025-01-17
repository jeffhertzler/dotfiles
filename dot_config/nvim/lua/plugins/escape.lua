return {
  "max397574/better-escape.nvim",
  opts = {
    timeout = 200,
    mappings = {
      t = {
        j = {
          k = function()
            if vim.bo.filetype == "snacks_terminal" then
              return "jk"
            end
            return "<esc>"
          end,
        },
      },
    },
  },
}
