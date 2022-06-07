local M = {}

function M.dark()
  vim.opt.background = "dark"
end

function M.light()
  vim.opt.background = "light"
end

function M.toggle()
  if vim.opt.background == "light" then
    M.dark()
  else
    M.light()
  end
end

function M.catppuccin()
  local catp = require('catppuccin');
  local colors = require('catppuccin.api.colors').get_colors();
  -- dump(colors)
  catp.remap({
    -- InclineNormal = { fg = colors.base, bg = colors.blue },
    -- InclineNormalNC = { fg = colors.text, bg = colors.base },
    NormalFloat = { bg = colors.none },
    WildMenu = { bg = colors.none },
  })
  catp.setup({
    integrations = {
      lsp_trouble = true,
      nvimtree = false,
      neotree = false,
      which_key = true,
      dashboard = false,
      bufferline = false,
      lightspeed = true,
      telekasten = false,
    }
  })
  vim.opt.laststatus = 3;
  require('feline').setup({
    components = require('catppuccin.core.integrations.feline')
  })
  -- require('feline').winbar.setup()
  require('incline').setup({
    render = function(props)
      local fill = props.focused and colors.blue or colors.surface0
      local text = props.focused and colors.base or colors.text
      return {
        { '', guifg = fill, guibg = colors.base },
        { ' ' .. string.gsub(vim.api.nvim_buf_get_name(props.buf), vim.loop.cwd() .. '/', '') .. ' ', guifg = text, guibg = fill }
      }
    end,
    window = {
      margin = {
        horizontal = 0,
        vertical = 0,
      },
      padding = {
        left = 0,
        right = 0,
      }
    }
  })
  vim.cmd [[colorscheme catppuccin]]
end

return M
