local M = {
  'catppuccin/nvim',
  name = 'catppuccin',
  lazy = false,
  opts = {
    flavour = 'mocha',
    background = {
      dark = 'mocha',
      light = 'latte',
    },
    compile_path = vim.fn.stdpath("cache") .. "/catppuccin",
    -- there is a built in way to get someothing like this now! theme = 'nvchad'
    custom_highlights = function(colors)
      return {
        FloatBorder = { bg = colors.mantle, fg = colors.mantle },
        LeapBackdrop = { fg = colors.surface2, style = { 'italic' } },
        NormalFloat = { bg = colors.mantle, fg = colors.text },
        Pmenu = { bg = colors.mantle, fg = colors.text },
        PmenuSel = { bg = colors.crust, bold = true },
        TelescopeMatching = { fg = colors.flamingo },
        TelescopeSelection = { fg = colors.text, bg = colors.surface0, bold = true },
        TelescopePromptPrefix = { bg = colors.crust },
        TelescopePromptNormal = { bg = colors.crust },
        TelescopeResultsNormal = { bg = colors.mantle },
        TelescopePreviewNormal = { bg = colors.mantle },
        TelescopePromptBorder = { bg = colors.crust, fg = colors.crust },
        TelescopeResultsBorder = { bg = colors.mantle, fg = colors.mantle },
        TelescopePreviewBorder = { bg = colors.mantle, fg = colors.mantle },
        TelescopePromptTitle = { bg = colors.pink, fg = colors.mantle },
        TelescopeResultsTitle = { bg = colors.sky, fg = colors.mantle },
        TelescopePreviewTitle = { bg = colors.green, fg = colors.mantle },
        TroubleNormal = { bg = colors.mantle, fg = colors.text },
      }
    end,
    integrations = {
      barbecue = false,
      dashboard = false,
      leap = true,
      lsp_trouble = true,
      mason = true,
      notify = true,
      nvimtree = false,
      treesitter_context = true,
      ts_rainbow = false,
      which_key = true,
    },
  },
}

M.colors = function()
  return require('catppuccin.palettes').get_palette()
end

M.highlights = function(fn)
  local colors = M.colors()

  local highlights = fn(colors)

  if not highlights then return end

  for hl, col in pairs(highlights) do
    vim.api.nvim_set_hl(0, hl, col)
  end
end

M.config = function(_, opts)
  require('catppuccin').setup(opts)
  vim.cmd [[colorscheme catppuccin]]
end

M.dark = function()
  vim.opt.background = "dark"
  vim.fn.jobstart("~/.config/tmux/bin/theme dark");
end

M.light = function()
  vim.opt.background = "light"
  vim.fn.jobstart("~/.config/tmux/bin/theme light");
end

M.toggle = function()
  if vim.opt.background:get() == "light" then
    M.dark()
  else
    M.light()
  end
end

return M
