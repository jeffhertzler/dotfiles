local wk = require('which-key');

local tb = require('telescope.builtin')
local te = require('telescope').extensions

local n_go_git = {
  d = { tb.lsp_definitions, 'definition' },
  h = { require('lspsaga.hover').render_hover_doc, 'hover' },
  i = { tb.lsp_implementations, 'implementation' },
  m = { [[:GitMessenger<cr>]], 'messenger' },
  r = { tb.lsp_references, 'references' },
  s = { require('lspsaga.signaturehelp').signature_help, 'signature' },
}

local normal = {
  g = n_go_git,
  ['<leader>'] = {
    b = {
      name = 'buffer',
      b = { function() tb.buffers({ show_all_buffers = true }) end, 'buffers' },
      d = { [[<cmd>Bdelete<cr>]], 'delete' },
      D = { [[<cmd>CBdelete other<cr>]], 'delete (others)' },
      l = { [[<cmd>buffers<cr>]], 'list' },
      n = { [[<cmd>bn<cr>]], 'next' },
      p = { [[<cmd>bp<cr>]], 'previous' },
      s = { tb.current_buffer_fuzzy_find, 'search' },
      w = { [[<cmd>w<cr>]], 'write' },
    },
    c = {
      name = 'code',
      a = { require('lspsaga.codeaction').code_action, 'actions' },
      d = { require('lspsaga.diagnostic').show_cursor_diagnostics, 'diagnostics (cursor)' },
      D = { require('lspsaga.diagnostic').show_line_diagnostics, 'diagnostics (line)' },
      e = {
        name = 'error',
        l = { tb.lsp_document_diagnostics, 'list' },
        L = { tb.lsp_workspace_diagnostics, 'list (workspace)' },
        n = { require('lspsaga.diagnostic').lsp_jump_diagnostic_next, 'next' },
        p = { require('lspsaga.diagnostic').lsp_jump_diagnostic_prev, 'prev' },
      },
      f = { [[<cmd>w | e | TSBufEnable highlight<cr>]], 'fix highlights' },
      o = { require('nvim-lsp-ts-utils').organize_imports, 'organize imports' },
      r = { require('lspsaga.rename').rename, 'rename' },
      s = { tb.lsp_document_symbols, 'symbols' },
      S = { tb.lsp_workspace_symbols, 'symbols (workspace)' },
      -- s = { [[:Telescope coc document_symbols<cr>]], 'symbols' },
      -- S = { [[:Telescope coc workspace_symbols<cr>]], 'symbols (workspace)' },
    },
    f = {
      name = 'file',
      b = { tb.file_browser, 'browser' },
      f = { function() tb.find_files({ hidden = true }) end, 'files' }, -- no git dir???
      D = { [[<cmd>!rm %<cr>:bd<cr>]], 'delete' },
      n = { [[:e %:p:h/]], 'new' },
      s = { [[<cmd>w<cr>]], 'save' },
      t = { [[<cmd>NvimTreeToggle<cr>]], 'tree' },
    },
    g = vim.tbl_extend('force', n_go_git, {
      name = 'go/git',
      b = { tb.git_branches, 'branches' },
      c = { tb.git_commits, 'commits' },
      C = { tb.git_bcommits, 'commits (buffer)' },
      g = { [[<cmd>LazyGit<cr>]], 'gui' },
      -- g = { require('neogit').open, 'gui' },
      s = { tb.git_status, 'status' },
    }),
    q = {
      name = 'quit',
      q = { [[<cmd>qa<cr>]], 'quit' },
      Q = { [[<cmd>qa!<cr>]], 'force quit' },
    },
    s = {
      name = 'search',
      [' '] = { tb.builtin, 'builtins' },
      b = { tb.buffers, 'buffers' },
      c = { tb.commands, 'commands' },
      C = { tb.command_history, 'command history' },
      d = { function() tb.live_grep({ cwd='%:p:h' }) end, 'directory' },
      f = { function() tb.find_files({ hidden = true }) end, 'files' },
      g = {
        name = 'git',
        b = { tb.git_branches, 'branches' },
        c = { tb.git_commits, 'commits' },
        C = { tb.git_bcommits, 'commits (buffer)' },
        s = { tb.git_status, 'status' },
      },
      G = {
        name = 'github',
        b = { tb.git_branches, 'branches' },
        g = { te.gh.gists, 'gists' },
        i = { te.gh.issues, 'issues' },
        p = { te.gh.pull_requests, 'pull requests' },
      },
      h = { tb.help_tags, 'help' },
      H = { tb.highlights, 'highlights' },
      -- H = { tb.search_history, 'history' }, -- not working?
      m = { tb.marks, 'marks' },
      p = { tb.live_grep, 'project' },
      r = { tb.registers, 'registers' },
      s = { tb.live_grep, 'search' },
      S = { tb.current_buffer_fuzzy_find, 'search (buffer)' },
      t = { tb.grep_string, 'this' },
    },
    t = {
      name = 'toggle',
      b = { [[<cmd>ToggleAlternate<cr>]], 'boolean' },
      h = { [[<cmd>TSBufToggle highlight<cr>]], 'highlight' },
    },
    v = {
      name = 'vim',
      e = { [[<cmd>e $MYVIMRC<cr>]], 'edit' },
      h = { [[<cmd>e ~/.config/nvim/lua/helpers.lua<cr>]], 'helpers' },
      k = { [[<cmd>e ~/.config/nvim/lua/keymaps.lua<cr>]], 'keymaps' },
      l = { [[<cmd>e ~/.local/share/nvim<cr>]], 'local' },
      p = { [[<cmd>e ~/.config/nvim/lua/plugins.lua<cr>]], 'plugins' },
      r = { [[<cmd>luafile ~/.config/nvim/init.lua<cr>]], 'reload' },
      s = { [[<cmd>e ~/.config/nvim/lua/settings.lua<cr>]], 'settings' },
      u = { [[<cmd>PackerSync<cr>]], 'update (plugins)' },
    },
    w = {
      name = 'window',
      c = { [[<cmd>close<cr>]], 'close' },
      h = { [[<cmd>sp<cr>]], 'horizontal split' },
      v = { [[<cmd>vs<cr>]], 'vertical split' },
    },
    z = {
      name = 'zsh',
      e = { [[<cmd>e ~/.zshrc<cr>]], 'edit' },
    },
    ['/'] = { tb.current_buffer_fuzzy_find, 'search (buffer)' },
  },
  ['<C-b>'] = { function() require('lspsaga.action').smart_scroll_with_saga(-1) end, 'back (diagnostics hover)' },
  ['<C-f>'] = { function() require('lspsaga.action').smart_scroll_with_saga(1) end, 'forward (diagnostics hover)' },
  ['<C-t>'] = { require('FTerm').toggle, 'terminal' },
  ['<C-_>'] = { [[<cmd>nohl<cr>]], 'clear search' },
  j = { 'gj', 'down' },
  k = { 'gk', 'up' },
  ['-'] = { [[<cmd>execute 'e ' .. expand('%:p:h')<cr>]], 'dir' },
}

local visual = {
  ['<leader>'] = {
    c = {
      name = 'code',
      a = { require('lspsaga.codeaction').range_code_action, 'actions' },
      s = { [[:!sort<cr>]], 'sort' },
    },
  },
  ['<'] = { '<gv', 'dedent' },
  ['>'] = { '>gv', 'indent' },
}

local terminal = {
  ['<C-t>'] = { require('FTerm').toggle, 'terminal' },
}

local comp = {
  ['<tab>'] = { function() require('plugins.snippets').complete('<tab>', 1) end, 'next' },
  -- ['<s-tab>'] = { function() require('plugins.snippets').complete('<s-tab>', -1) end, 'prev' },
  ['<s-tab>'] = { function() require('luasnip').jump(-1) end, 'prev' },
}

local insert = vim.tbl_extend('force', comp, {
  ['<cr>']  = { [[compe#confirm('<cr>')]], 'confirm', expr = true },
  ['<esc>'] = { function() require('plugins.completion').close('<esc>') end, 'exit'},
  ['<C-c>'] = { function() require('plugins.completion').close('<C-c>') end, 'exit'},
  ['<C-j>'] = { function() require('plugins.completion').pum('<C-j>', '<C-n>') end, 'next' },
  ['<C-k>'] = { function() require('plugins.completion').pum('<C-k>', '<C-p>') end, 'prev' },
})

local select = vim.tbl_extend('force', comp, {})

wk.register(insert,   { mode = "i", silent = false })
wk.register(normal,   { mode = "n", silent = false })
wk.register(select,   { mode = "s", silent = false })
wk.register(terminal, { mode = "t", silent = false })
wk.register(visual,   { mode = "x", silent = false })
