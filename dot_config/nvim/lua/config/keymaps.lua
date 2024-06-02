local mk = require('config.utils').make_keymap

local n = mk('n')
local nt = mk({ 'n', 't' })
local v = mk('v')

n('<leader>bl', '<cmd>buffers<cr>', 'list')
n('<leader>bn', '<cmd>bn<cr>', 'next')
n('<leader>bp', '<cmd>bp<cr>', 'prev')
n('<leader>bw', '<cmd>w<cr>', 'write')

n('<leader>dve', '<cmd>e ~/.config/nvim/init.lua<cr>', 'edit')
n('<leader>dvl', '<cmd>e ~/.local/share/nvim<cr>', 'local')
n('<leader>dvp', '<cmd>e ~/.config/nvim/lua/plugins<cr>', 'plugins')
n('<leader>dvr', '<cmd>luafile ~/.config/nvim/init.lua<cr>', 'reload')
n('<leader>dvs', '<cmd>e ~/.config/nvim/lua/config/settings.lua<cr>', 'settings')

n('<leader>dte', '<cmd>e ~/.config/tmux/tmux.conf<cr>', 'edit')

n('<leader>dze', '<cmd>e ~/.zshrc<cr>', 'edit')
n('<leader>dzp', '<cmd>e ~/.private.zsh<cr>', 'edit')

-- n('<leader>fD', '<cmd>!rm %<cr>:bd<cr>', 'delete')
n('<leader>fn', ':e %:p:h/', 'new')
n('<leader>fs', '<cmd>w<cr>', 'save')

n('<leader>qq', '<cmd>qa<cr>', 'quit')
n('<leader>qQ', '<cmd>qa!<cr>', 'quit (force)')

n('<leader>pp', '<cmd>:Lazy<cr>', 'Lazy')
n('<leader>pm', '<cmd>:Mason<cr>', 'Mason')

n('<leader>tt', function() require('plugins.theme').toggle() end, 'theme')

n('<leader>wc', '<cmd>close<cr>', 'close')
n('<leader>wsh', '<cmd>sp<cr>', 'horizontal')
n('<leader>wsv', '<cmd>vs<cr>', 'vertical')

n('<C-/>', '<cmd>nohl<cr>', 'save')
n('<C-_>', '<cmd>nohl<cr>', 'save')

nt('<C-t>', function() require('FTerm').toggle() end, 'terminal')

n('<A-l>', '<cmd>:vsplit<cr>', 'split (vertical)')
n('<A-j>', '<cmd>:split<cr>', 'split (horizontal)')

v('<', '<gv', 'dedent')
v('>', '>gv', 'indent')

v('<leader>cs', ':!sort<cr>', 'sort')
