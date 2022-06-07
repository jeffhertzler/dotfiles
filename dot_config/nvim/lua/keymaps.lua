local wk = require('which-key');
local legendary = require('legendary');

local tb = require('telescope.builtin')
local te = require('telescope').extensions
-- local tt = require('telescope.themes')

local chezmoi = '~/.local/share/chezmoi'

-- TODO: save and optionally add to chezmoi if in allowlist
-- local save_and_add = function()
-- end

local n_go_git = {
  d = { tb.lsp_definitions, 'definition' },
  h = { function() vim.lsp.buf.hover() end, 'hover' },
  i = { tb.lsp_implementations, 'implementation' },
  m = { [[:GitMessenger<cr>]], 'messenger' },
  r = { tb.lsp_references, 'references' },
  s = { function() vim.lsp.buf.signature_help() end, 'signature' },
}

local normal = {
  g = n_go_git,
  ['<leader>'] = {
    ['<leader>'] = { function() require('legendary').find() end, 'legendary' },
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
      a = { function() vim.lsp.buf.code_action() end, 'actions' },
      d = { function() vim.diagnostic.open_float({ scope = 'c', border = 'rounded' }) end, 'diagnostics (cursor)' },
      D = { function() vim.diagnostic.open_float({ border = 'rounded' }) end, 'diagnostics (line)' },
      e = {
        name = 'error',
        l = { function() tb.diagnostics({ bufnr = 0 }) end, 'list' },
        L = { function() tb.diagnostics() end, 'list (workspace)' },
        n = { function() vim.diagnostic.goto_next() end, 'next' },
        p = { function() vim.diagnostic.goto_prev() end, 'prev' },
      },
      f = { function() require("plugins.lsp").format() end, 'format' },
      F = { [[<cmd>w | e | TSBufEnable highlight<cr>]], 'fix highlights' },
      l = {
        name = 'lens',
        a = { function() vim.lsp.codelens.run() end, 'actions' },
        r = { function() vim.lsp.codelens.refresh() end, 'refresh' },
      },
      o = { require('nvim-lsp-ts-utils').organize_imports, 'organize imports' },
      r = { function() vim.lsp.buf.rename() end, 'rename' },
      s = { tb.lsp_document_symbols, 'symbols' },
      S = { tb.lsp_workspace_symbols, 'symbols (workspace)' },
    },
    d = {
      name = 'dotfiles',
      c = {
        name = 'chezmoi',
        a = { [[<cmd>silent !chezmoi add %:p<cr>]], 'add' },
        c = { function() tb.find_files({ search_dirs = { chezmoi } }) end, 'files' },
        C = { function() tb.live_grep({ search_dirs = { chezmoi } }) end, 'search' },
        d = { [[<cmd>e ]] .. chezmoi .. [[ <cr>]], 'cd' },
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
        v = { function() tb.find_files({ search_dirs = { '~/.config/nvim' } }) end, 'files' },
        V = { function() tb.live_grep({ search_dirs = { '~/.config/nvim' } }) end, 'search' },
        u = { [[<cmd>PackerSync<cr>]], 'update (plugins)' },
      },
      z = {
        name = 'chezmoiz/zsh',
        e = { [[<cmd>e ~/.zshrc<cr>]], 'edit' },
      },
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
    h = { name = "gitsigns" },
    m = {
      name = "music",
      [' '] = { [[<Plug>(SpotifyPause)]], 'pause' },
      d = { [[<cmd>SpotifyDevices<cr>]], 'device', },
      m = { [[<cmd>Spotify<cr>]], 'search', },
      n = { [[<Plug>(SpotifySkip)]], 'next' },
    },
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
      d = { function() tb.live_grep({ cwd = '%:p:h' }) end, 'directory' },
      D = { function() tb.find_files({ cwd = '%:p:h', hidden = true }) end, 'directory (files)' },
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
      t = { require('plugins.theme').toggle, 'theme' },
      b = { [[<cmd>ToggleAlternate<cr>]], 'boolean' },
      h = { [[<cmd>TSBufToggle highlight<cr>]], 'highlight' },
    },
    w = {
      name = 'window',
      c = { [[<cmd>close<cr>]], 'close' },
      h = { [[<cmd>sp<cr>]], 'horizontal split' },
      v = { [[<cmd>vs<cr>]], 'vertical split' },
    },
    ['/'] = { tb.current_buffer_fuzzy_find, 'search (buffer)' },
  },
  -- ['<C-b>'] = { function() require('lspsaga.action').smart_scroll_with_saga(-1) end, 'back (diagnostics hover)' },
  -- ['<C-f>'] = { function() require('lspsaga.action').smart_scroll_with_saga(1) end, 'forward (diagnostics hover)' },
  ['<C-t>'] = { require('FTerm').toggle, 'terminal' },
  ['<C-_>'] = { [[<cmd>nohl<cr>]], 'clear search' },
  j = { 'gj', 'down' },
  k = { 'gk', 'up' },
  ['-'] = { [[<cmd>execute 'e ' .. expand('%:p:h')<cr>]], 'dir' },
  -- ['-'] = { function() require('lir.float').toggle() end, 'dir' },
}

local visual = {
  ['<leader>'] = {
    c = {
      name = 'code',
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
  ['<s-tab>'] = { function() require('plugins.snippets').complete('<s-tab>', -1) end, 'prev' },
  -- ['<s-tab>'] = { function() require('luasnip').jump(-1) end, 'prev' },
}

local insert = vim.tbl_extend('force', comp, {
  -- ['<bs>'] = { function() require('plugins.completion').pum('<bs>', '<C-e><bs>') end, 'exit'},
  -- ['<cr>']  = {
  --   function()
  --     require('plugins.completion').pum('<cr>', function()
  --       if vim.fn.complete_info().selected == -1 then
  --         require('helpers').feedkeys('<C-e><cr>')
  --       else
  --         require('helpers').feedkeys('<C-y>')
  --       end
  --     end)
  --   end,
  --   'confirm'
  -- },
  -- ['<esc>'] = { function() require('plugins.completion').pum('<esc>', '<C-e><esc>') end, 'exit'},
  -- ['<C-c>'] = { function() require('plugins.completion').pum('<C-c>', '<C-e><C-c>') end, 'exit'},
  -- ['<C-j>'] = { function() require('plugins.completion').pum('<C-j>', '<C-n>') end, 'next' },
  -- ['<C-k>'] = { function() require('plugins.completion').pum('<C-k>', '<C-p>') end, 'prev' },
  -- ['<cr>']  = { [[compe#confirm('<cr>')]], 'confirm', expr = true },
  -- ['<esc>'] = { function() require('plugins.completion').close('<esc>') end, 'exit'},
  -- ['<C-c>'] = { function() require('plugins.completion').close('<C-c>') end, 'exit'},
  -- ['<C-j>'] = { function() require('plugins.completion').pum('<C-j>', '<C-n>') end, 'next' },
  -- ['<C-k>'] = { function() require('plugins.completion').pum('<C-k>', '<C-p>') end, 'prev' },
})

local select = vim.tbl_extend('force', comp, {})

legendary.setup()

wk.register(insert, { mode = "i", silent = false })
wk.register(normal, { mode = "n", silent = false })
wk.register(select, { mode = "s", silent = false })
wk.register(terminal, { mode = "t", silent = false })
wk.register(visual, { mode = "x", silent = false })
