" Not vi compatible
set nocompatible

"-------------VimVsNeoVim--------------"

if has('nvim')
  let s:editor_root=expand('~/.config/nvim')
else
  let s:editor_root=expand('~/.vim')
endif





"-------------Plug--------------"

" Automatic Plug setup
if empty(glob(s:editor_root . '/autoload/plug.vim'))
  silent execute '!curl -fLo ' . s:editor_root . '/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall
endif

call plug#begin(s:editor_root . '/plugged')

  " Color Scheme
  Plug 'chriskempson/base16-vim'

  " Git
  Plug 'airblade/vim-gitgutter'
  Plug 'tpope/vim-fugitive'

  " Status bar
  Plug 'vim-airline/vim-airline'
  Plug 'vim-airline/vim-airline-themes'

  " Spacing
  Plug 'ntpeters/vim-better-whitespace'
  Plug 'nathanaelkane/vim-indent-guides'

  " Formatting
  Plug 'editorconfig/editorconfig-vim'

  " Code completion
  if has('nvim')
    Plug 'Shougo/deoplete.nvim'
  else
    Plug 'Shougo/neocomplete.vim'
  endif

  " Snippets
  Plug 'SirVer/ultisnips'

  " Comments
  Plug 'tpope/vim-commentary'

  " Fuzzy search
  Plug '/usr/local/opt/fzf' | Plug 'junegunn/fzf.vim'

  " Better / search
  Plug 'junegunn/vim-pseudocl'
  Plug 'junegunn/vim-oblique'
  " Plug 'rking/ag.vim'

  " File browsing
  Plug 'tpope/vim-vinegar'
  Plug 'tpope/vim-eunuch'
  Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }

  " Motions
  Plug 'Lokaltog/vim-easymotion'

  " Text objects
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-repeat'
  Plug 'tpope/vim-unimpaired'

  " Alignment
  Plug 'junegunn/vim-easy-align', { 'on': ['<plug>(EasyAlign)', 'EasyAlign'] }

  " Auto-close parens/braces/etc
  Plug 'jiangmiao/auto-pairs'

  " Multiple cursors
  Plug 'terryma/vim-multiple-cursors'

  " Emmet
  Plug 'mattn/emmet-vim'

  " Syntaxes
  Plug 'sheerun/vim-polyglot'
  Plug 'ElmCast/elm-vim'
  Plug 'w0rp/ale'

  " Elixir
  Plug 'slashmili/alchemist.vim'

call plug#end()






"-------------Vim Directories--------------"

function! InitializeDirectories()
  let parent=$HOME
  let dir_list={
    \ 'backup': 'backupdir',
    \ 'views': 'viewdir',
    \ 'swap': 'directory'}

  if has('persistent_undo')
    let dir_list['undo']='undodir'
  endif

  exec 'set viminfo+=n' . s:editor_root . '/viminfo'

  for [dirname, settingname] in items(dir_list)
    let directory=s:editor_root . '/' . dirname . '/'
    if exists("*mkdir")
      if !isdirectory(directory)
        call mkdir(directory)
      endif
    endif
    if !isdirectory(directory)
      echo 'Warning: Unable to create directory: ' . directory
      echo 'Try: mkdir -p ' . directory
    else
      let directory=substitute(directory, ' ', '\\ ', 'g')
      exec 'set ' . settingname . '=' . directory . '/'
    endif
  endfor
endfunction
call InitializeDirectories()





"-------------Basics--------------"

" Encoding
if !has('nvim')
  set encoding=utf-8
endif

" Mouse
set mouse=a
set mousehide

" Code folding off
set nofoldenable

" Syntax highlighting
syntax enable

" Expected backspace functionality
set backspace=indent,eol,start

" Indent settings per file type
filetype plugin indent on

" Default split management
set splitbelow
set splitright

" Case insensitive search unless uppercase is typed
set ignorecase
set smartcase

" Soft wordwrap
set wrap
set linebreak
set nolist
set textwidth=0
set wrapmargin=0

" Indent
set autoindent
set shiftwidth=2
set expandtab
set tabstop=2
set softtabstop=2

" Allow for cursor beyond last character
set virtualedit=onemore

" Spell check
set spell

" Allow buffer switching without saving
set hidden

" End of word designators
set iskeyword-=.
set iskeyword-=#
set iskeyword-=-
set iskeyword-=_

" copy/paste
set clipboard^=unnamed,unnamedplus

" diff
set diffopt=iwhite






"-------------Visuals--------------"

" Color settings
set background=dark
set t_CO=256
let base16colorspace=256
silent! colorscheme base16-dracula
set termguicolors

" Line numbers
set number
set relativenumber

" Airline already shows the mode
set noshowmode

" Show matching brackets/parenthesis
set showmatch

" Highlight current line
set cursorline





"-------------Mappings--------------"

" Leader remaps
let mapleader="\<space>"
let maplocalleader=','

" Sane pasting
set pastetoggle=<f12>

" Wrapped lines go down/up to next row, rather than next line in file.
noremap j gj
noremap k gk

" Quick config edit
nmap <leader>ve :tabedit $MYVIMRC<cr>
nmap <leader>ze :tabedit $HOME/.zshrc<cr>

" Easier escape
inoremap fd <esc>
" Easier <c-[>
noremap <c-g> <c-[>

" Easier colon
nnoremap ; :
vnoremap ; :
nnoremap ;; ;
vnoremap ;; ;

" quick eol colon
inoremap <leader>; <c-o>m`<c-o>A;<c-o>``
nnoremap <leader>; m`A;<esc>``

" Easier save & quit
command! WQ wq
command! Wq wq
command! W w
command! Q q
inoremap <c-s> <esc>:up<cr>
nnoremap <c-s> :up<cr>
vnoremap <c-s> <esc>:up<cr>
inoremap <c-q> <esc>:q<cr>
nnoremap <c-q> :q<cr>
vnoremap <c-q> <esc>:q<cr>

" Less accidental macros
" nnoremap m q
" nnoremap q <nop>

" Insert line above/below
nnoremap <c-j> o<esc>k
nnoremap <c-k> O<esc>j

" Stay in visual mode when indenting
vnoremap > >gv
vnoremap < <gv

" Resize splits in larger chunks
nnoremap <c-w>> :vertical resize +10<cr>
nnoremap <c-w>< :vertical resize -10<cr>

" Spacemacs window movement
nnoremap <leader>wl <c-w>l
nnoremap <leader>wk <c-w>k
nnoremap <leader>wj <c-w>j
nnoremap <leader>wh <c-w>h





"-------------Plugin Settings--------------"

" Airline
let airline_theme='base16'
let airline_powerline_fonts=1
set laststatus=2

" Better whitespace
let strip_whitespace_on_save=1

" Indent guides
let indent_guides_enable_on_vim_startup=1
let indent_guides_auto_colors=0
autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd   ctermbg=00
autocmd VimEnter,Colorscheme * :hi IndentGuidesEven  ctermbg=18

" FZF
nnoremap <silent> <expr> <leader>pf (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":FZF\<cr>"
nnoremap <silent> <expr> <leader>bb (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Buffers\<cr>"
nnoremap <silent> <expr> <leader>sp (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Ag\<cr>"
" nnoremap <silent> <expr> <leader>r (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":BTags\<cr>"
" nnoremap <silent> <expr> <leader>f (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Tags\<cr>"
" nnoremap <silent> <expr> <leader>h (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":History\<cr>"

" Nerd Tree
nnoremap <leader>kb :NERDTreeToggle<cr>
let NERDTreeHijackNetrw=0
let NERDTreeShowHidden=1

" Multi Cursor
let multi_cursor_insert_maps={ 'j':1 }

" Easy Align
let g:easy_align_ignore_groups=['String']
xmap ga <plug>(EasyAlign)
nmap ga <plug>(EasyAlign)

" Completion
let g:UltiSnipsExpandTrigger="<c-e>"
let g:UltiSnipsJumpForwardTrigger="<c-l>"
let g:UltiSnipsJumpBackwardTrigger="<c-h>"
if has('nvim')
  let g:deoplete#enable_at_startup=1
  inoremap <silent><expr><tab> pumvisible() ? "\<c-n>" :
    \ <SID>check_back_space() ? "\<tab>" :
    \ deoplete#mappings#manual_complete()
  inoremap <silent><expr><cr> pumvisible() ?
    \ (len(keys(UltiSnips#SnippetsInCurrentScope())) > 0 ?
    \ deoplete#mappings#close_popup()."\<c-c>l:call UltiSnips#ExpandSnippet()\<cr>" :
    \ deoplete#mappings#close_popup()) : "\<cr>"
else
  let g:neocomplete#enable_at_startup=1
  inoremap <silent><expr><tab> pumvisible() ? "\<c-n>" :
    \ <SID>check_back_space() ? "\<tab>" :
    \ neocomplete#mappings#manual_complete()
  inoremap <silent><expr><cr> pumvisible() ?
    \ (len(keys(UltiSnips#SnippetsInCurrentScope())) > 0 ?
    \ neocomplete#mappings#close_popup()."\<c-c>l:call UltiSnips#ExpandSnippet()\<cr>" :
    \ neocomplete#mappings#close_popup()) : "\<cr>"
endif
function! s:check_back_space()
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~ '\s'
endfunction

" Polyglot
let g:polyglot_disabled = ['elm']

" Auto Pairs
let g:AutoPairsShortcutBackInsert = '<C-b>'





"-------------Auto-Commands--------------"

" Retab on save
augroup autoretab
  autocmd!
  autocmd BufWrite * %retab
augroup END

" Autoreload externally edited file
augroup autoreload
  autocmd!
  autocmd CursorHold,CursorHoldI * checktime
augroup END
