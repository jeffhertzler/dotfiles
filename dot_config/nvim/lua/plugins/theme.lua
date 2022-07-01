local M = {}

function M.dark()
  vim.opt.background = "dark"
  vim.cmd("Catppuccin mocha");
end

function M.light()
  vim.opt.background = "light"
  vim.cmd("Catppuccin latte");
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
  catp.remap({
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
      local text = props.focused and colors.base or colors.blue

      local bufname = vim.api.nvim_buf_get_name(props.buf)
      local res = bufname ~= '' and vim.fn.fnamemodify(bufname, ':t') or '[No Name]'
      local icon = require('nvim-web-devicons').get_icon(res, vim.fn.expand('%:e'))

      if vim.api.nvim_buf_get_option(props.buf, 'modified') then
        fill = props.focused and colors.mauve or fill
        text = props.focused and text or colors.mauve
      end

      return {
        { '', guifg = fill, guibg = colors.base },
        { icon, guifg = text, guibg = fill },
        { ' ' .. res .. ' ', guifg = text, guibg = fill }
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
