local starts_with = function(str, prefix)
  if str == nil or prefix == nil then
    return false
  elseif #str < #prefix then
    return false
  else
    return str:sub(1, #prefix) == prefix
  end
end

local oil_dir = function(bufname)
  local oil = 'oil://'
  local is_dir = starts_with(bufname, oil)
  return is_dir, bufname:gsub(oil, '')
end

local paths = function(bufname)
  return vim.split(bufname, '/')
end

local join = function(list)
  local full
  for i, path in ipairs(list) do
    if i == 1 then
      full = path
    else
      full = full .. '/' .. path
    end
  end
  return full
end

return {
  {
    'b0o/incline.nvim',
    event = 'VeryLazy',
    config = function()
      vim.opt.laststatus = 3;
      require('incline').setup({
        ignore = {
          buftypes = function(bufnr, buftype)
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            local is_dir = oil_dir(bufname)
            return not (buftype == '' or is_dir)
          end,
        },
        render = function(props)
          local colors = require('plugins.theme').colors();
          local icons = require('nvim-web-devicons')

          local fill = props.focused and colors.blue or colors.surface0
          local text = props.focused and colors.base or colors.blue

          local bufname = vim.api.nvim_buf_get_name(props.buf)
          local is_dir, full_name = oil_dir(bufname)
          local name = vim.fn.fnamemodify(full_name, ':~')
          local fname = vim.fn.fnamemodify(name, ':t')
          local ext = vim.fn.fnamemodify(name, ':e')
          local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':~')
          local relative_path = name:sub(#cwd + 1, -1)
          local in_cwd = starts_with(name, cwd)
          local cwd_list = paths(cwd)
          local name_list = in_cwd and paths(relative_path) or paths(name)
          local cwd_last = table.remove(cwd_list, #cwd_list)
          local dir_last = table.remove(name_list, #name_list - 1)
          if (fname ~= '') then
            table.remove(name_list, #name_list)
            table.insert(name_list, '')
          end
          local middle = dir_last ~= '' and vim.fn.pathshorten(join(name_list)) or ''

          local front = in_cwd and cwd_last or ''
          local mid = middle .. dir_last .. '/'
          local icon = is_dir and '' or icons.get_icon(fname, ext, { default = true })

          if vim.api.nvim_buf_get_option(props.buf, 'modified') then
            fill = props.focused and colors.mauve or fill
            text = props.focused and text or colors.mauve
          end

          return {
            { '', guifg = fill, guibg = colors.base },
            { icon .. ' ', guifg = text, guibg = fill },
            { front, guifg = text, guibg = fill, gui = 'bold' },
            { mid, guifg = text, guibg = fill },
            { fname .. ' ', guifg = text, guibg = fill, gui = 'bold' },
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
          },
        },
      })
    end,
  },
  {
    'freddiehaddad/feline.nvim',
    event = 'BufReadPre',
    config = function()
      local ctp_feline = require('catppuccin.groups.integrations.feline')
      require('feline').setup({
        components = ctp_feline.get(),
      })
    end,
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    event = 'BufReadPre',
    opts = {
      indent = {
        char = '│',
      },
      exclude = {
        filetypes = { 'gitmessengerpopup', 'help', 'lspinfo', 'Trouble' },
      },
      scope = {
        enabled = false,
      },
    },
  }
}
