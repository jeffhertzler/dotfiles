local helpers = require('helpers')
local keymap = helpers.keymap
local map_from_table = helpers.map_from_table

local go = {
  ['%'] = {
    name = 'matchit backward',
  },
  c = {
    name = 'comment (with motion)'
  },
  cc = {
    name = 'comment (line)'
  },
  d = {
    name = 'definition',
    action = [[<Plug>(coc-definition)]],
    opts = { silent = true },
  },
  D = {
    name = 'declaration',
    action = [[<Plug>(coc-declaration)]],
    opts = { silent = true },
  },
  h = {
    name = 'hover',
    action = [[:call CocActionAsync('doHover')<cr>]],
    opts = { noremap = true, silent = true },
  },
  i = {
    name = 'implementation',
    action = [[<Plug>(coc-implementation)]],
    opts = { silent = true },
  },
  m = {
    name = 'messenger',
    action = [[:GitMessenger<cr>]],
    opts = { noremap = true, silent = true },
  },
  r = {
    name = 'references',
    action = [[<Plug>(coc-references)]],
    opts = { silent = true },
  },
  y = {
    name = 'type',
    action = [[<Plug>(coc-type-definition)]],
    opts = { silent = true },
  },
}

local leader = {
  b = {
    name = 'buffer',
    keys = {
      b = {
        name = 'buffers',
        action = [[:Telescope buffers show_all_buffers=true<cr>]],
        opts = { noremap = true },
      },
      d = {
        name = 'delete',
        action = [[:Bdelete<cr>]],
        opts = { noremap = true },
      },
      l = {
        name = 'list',
        action = [[:buffers<cr>]],
        opts = { noremap = true },
      },
      n = {
        name = 'next',
        action = [[:bn<cr>]],
        opts = { noremap = true },
      },
      p = {
        name = 'previous',
        action = [[:bp<cr>]],
        opts = { noremap = true },
      },
      s = {
        name = 'search',
        action = [[:Telescope current_buffer_fuzzy_find<cr>]],
        opts = { noremap = true },
      },
      w = {
        name = 'write',
        action = [[:w<cr>]],
        opts = { noremap = true },
      },
    },
  },
  c = {
    name = 'code',
    keys = {
      a = {
        name = 'action',
        action = [[<Plug>(coc-codeaction-line)]],
      },
      e = {
        name = 'error',
        keys = {
          l = {
            name= 'list',
            action = [[:CocList diagnostics<cr>]],
            opts = { noremap = true },
          },
        },
      },
      o = {
        name = 'organize imports',
        action = [[:call CocAction('runCommand', 'editor.action.organizeImport')<cr>]],
        opts = { noremap = true },
      },
      r = {
        name = 'rename',
        action = [[<Plug>(coc-rename)]],
      },
    },
  },
  f = {
    name = 'file',
    keys = {
      f = {
        name = 'files',
        action = [[:lua require('telescope.builtin').find_files({ hidden = true })<cr>]],
        opts = { noremap = true, silent = true },
      },
      D = {
        name = 'delete',
        action = [[:!rm %<cr>:bd<cr>]],
        opts = { noremap = true, silent = true },
      },
      n = {
        name = 'new',
        action = [[:e %:p:h/]],
        opts = { noremap = true },
      },
      s = {
        name = 'save',
        action = [[:w<cr>]],
        opts = { noremap = true },
      },
      t = {
        name = 'tree',
        action = [[:NvimTreeToggle<cr>]],
        opts = { noremap = true },
      },
    },
  },
  g = {
    name = 'go/git',
    keys = vim.fn.extend(go, {
      b = {
        name = 'branches',
        action = [[:Telescope git_branches<cr>]],
        opts = { noremap = true },
      },
      c = {
        name = 'commits',
        action = [[:Telescope git_commits<cr>]],
        opts = { noremap = true },
      },
      C = {
        name = 'commits (buffer)',
        action = [[:Telescope git_bcommits<cr>]],
        opts = { noremap = true },
      },
      g = {
        name = 'gui',
        action = [[:LazyGit<cr>]],
        opts = { noremap = true },
      },
      s = {
        name = 'status',
        action = [[:Telescope git_status<cr>]],
        opts = { noremap = true },
      },
    }),
  },
  q = {
    name = 'quit',
    keys = {
      q = {
        name = 'quit',
        action = [[:qa<cr>]],
        opts = { noremap = true },
      },
      Q = {
        name = 'force quit',
        action = [[:qa!<cr>]],
        opts = { noremap = true },
      },
    }
  },
  s = {
    name = 'search',
    keys = {
      b = {
        name = 'buffers',
        action = [[:Telescope buffers<cr>]],
        opts = { noremap = true },
      },
      c = {
        name = 'commands',
        action = [[:Telescope commands<cr>]],
        opts = { noremap = true },
      },
      C = {
        name = 'command history',
        action = [[:Telescope command_history<cr>]],
        opts = { noremap = true },
      },
      d = {
        name = 'directory',
        action = [[:Telescope live_grep cwd=%:p:h<cr>]],
        opts = { noremap = true },
      },
      D = {
        name = 'diffs',
        action = [[:Telescope git_status<cr>]],
        opts = { noremap = true },
      },
      f = {
        name = 'files',
        action = [[:Telescope git_files<cr>]],
        opts = { noremap = true },
      },
      g = {
        name = 'git',
        keys = {
          b = {
            name = 'buffer commits',
            action = [[:Telescope git_bcommits<cr>]],
            opts = { noremap = true },
          },
          c = {
            name = 'commits',
            action = [[:Telescope git_commits<cr>]],
            opts = { noremap = true },
          },
        },
      },
      G = {
        name = 'github',
        keys = {
          g = {
            name = 'gists',
            action = [[:Telescope gh gists<cr>]],
            opts = { noremap = true },
          },
          i = {
            name = 'issues',
            action = [[:Telescope gh issues<cr>]],
            opts = { noremap = true },
          },
          p = {
            name = 'pull requests',
            action = [[:Telescope gh pull_requests<cr>]],
            opts = { noremap = true },
          },
        },
      },
      h = {
        name = 'help',
        action = [[:Telescope help_tags<cr>]],
        opts = { noremap = true },
      },
      m = {
        name = 'marks',
        action = [[:Telescope marks<cr>]],
        opts = { noremap = true },
      },
      p = {
        name = 'project',
        action = [[:Telescope live_grep<cr>]],
        opts = { noremap = true },
      },
      s = {
        name = 'search',
        action = [[:Telescope live_grep<cr>]],
        opts = { noremap = true },
      },
      S = {
        name = 'search (buffer)',
        action = [[:Telescope current_buffer_fuzzy_find<cr>]],
        opts = { noremap = true },
      },
      t = {
        name = 'this',
        action = [[:Telescope grep_string<cr>]],
        opts = { noremap = true },
      },
    },
  },
  v = {
    name = 'vim',
    keys = {
      e = {
        name = 'edit',
        action = [[:e $MYVIMRC<cr>]],
        opts = { noremap = true },
      },
      h = {
        name = 'helpers',
        action = [[:e ~/.config/nvim/lua/helpers.lua<cr>]],
        opts = { noremap = true },
      },
      k = {
        name = 'keymaps',
        action = [[:e ~/.config/nvim/lua/keymaps.lua<cr>]],
        opts = { noremap = true },
      },
      p = {
        name = 'plugins',
        action = [[:e ~/.config/nvim/lua/plugins.lua<cr>]],
        opts = { noremap = true },
      },
      r = {
        name = 'reload',
        action = [[:luafile $MYVIMRC<cr>]],
        opts = { noremap = true },
      },
      s = {
        name = 'settings',
        action = [[:e ~/.config/nvim/lua/settings.lua<cr>]],
        opts = { noremap = true },
      },
      u = {
        name = 'update (plugins)',
        action = [[:PackerSync<cr>]],
        opts = { noremap = true },
      },
    },
  },
  w = {
    name = 'window',
    keys = {
      c = {
        name = 'close',
        action = [[:close<cr>]],
        opts = { noremap = true },
      },
      h = {
        name = 'horizontal split',
        action = [[:sp<cr>]],
        opts = { noremap = true },
      },
      v = {
        name = 'vertical split',
        action = [[:vs<cr>]],
        opts = { noremap = true },
      },
    },
  },
  z = {
    name = 'zsh',
    keys = {
      e = {
        name = 'edit',
        action = [[:e ~/.zshrc<cr>]],
        opts = { noremap = true },
      },
      r = {
        name = 'reload',
        action = [[:silent !source ~/.zshrc<cr>]],
        opts = { noremap = true },
      },
    },
  },
}

vim.g.leader_map = map_from_table('n', leader, '<leader>')
vim.g.g_map = map_from_table('n', go, 'g')

vim.fn['which_key#register']('<Space>', 'g:leader_map')
vim.fn['which_key#register']('g', 'g:g_map')

keymap('n', '<leader>', [[:<c-u>WhichKey '<Space>'<cr>]], { silent = true, noremap = true })
keymap('n', 'g', [[:<c-u>WhichKey 'g'<cr>]], { silent = true, noremap = true })

-- autocomplete
keymap('i', '<esc>', [[pumvisible() ? "\<C-e>" : "\<esc>"]], { noremap = true, expr = true })
keymap('i', '<cr>',  [[pumvisible() ? "\<C-y>" : "\<cr>"]], { noremap = true, expr = true })
keymap('i', '<C-j>', [[pumvisible() ? "\<C-n>" : "\<C-j>"]], { noremap = true, expr = true })
keymap('i', '<C-k>', [[pumvisible() ? "\<C-p>" : "\<C-k>"]], { noremap = true, expr = true })

-- diagnostics scroll
keymap('n', '<C-f>', [[coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"]], { noremap = true, silent = true, expr = true, nowait = true })
keymap('n', '<C-b>', [[coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-f>"]], { noremap = true, silent = true, expr = true, nowait = true })
keymap('i', '<C-f>', [[coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"]], { noremap = true, silent = true, expr = true, nowait = true })
keymap('i', '<C-b>', [[coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"]], { noremap = true, silent = true, expr = true, nowait = true })
keymap('v', '<C-f>', [[coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"]], { noremap = true, silent = true, expr = true, nowait = true })
keymap('v', '<C-b>', [[coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-f>"]], { noremap = true, silent = true, expr = true, nowait = true })

-- terminal
keymap('n', '<C-t>', [[:FTermToggle<cr>]], { noremap = true })
keymap('t', '<C-t>', [[<C-\><C-n>:FTermToggle<cr>]], { noremap = true })

-- wordrap
keymap('n', 'j', 'gj', { noremap = true })
keymap('n', 'k', 'gk', { noremap = true })

-- clear search highlight - <C-_> is actually <C-/> :shrug:
keymap('n', '<C-_>', ':nohl<cr>', { noremap = true })

-- i wan't to change indent multiple times while in visual mode easier
keymap('v', '<', '<gv', { noremap = true })
keymap('v', '>', '>gv', { noremap = true })
