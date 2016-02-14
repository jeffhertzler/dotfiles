" Not vi compatible, must be first
set nocompatible





"-------------Plug--------------"

" Automatic Plug setup
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall | source $MYVIMRC
endif

call plug#begin('~/.vim/plugged')

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
  function! BuildYCM(info)
    if a:info.status == 'installed' || a:info.force
      !npm install -g tern
      !./install.py --tern-completer
    endif
  endfunction
  Plug 'Valloric/YouCompleteMe', { 'do': function('BuildYCM') }

  " Snippets
  Plug 'SirVer/ultisnips'

  " Comments
  Plug 'tpope/vim-commentary', { 'on': '<Plug>Commentary' }

  " Fuzzy search
  Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
  Plug 'junegunn/fzf.vim'

  " Better / search
  Plug 'junegunn/vim-pseudocl'
  Plug 'junegunn/vim-oblique'
  Plug 'rking/ag.vim'

  " File browsing
  Plug 'tpope/vim-vinegar'
  Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }

  " Motions
  Plug 'Lokaltog/vim-easymotion'

  " Text objects
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-repeat'

  " Alignment
  Plug 'junegunn/vim-easy-align', { 'on': ['<Plug>(EasyAlign)', 'EasyAlign'] }

  " Multiple cursors
  Plug 'terryma/vim-multiple-cursors'

call plug#end()





"-------------Vim Directories--------------"

function! InitializeDirectories()
  let parent=$HOME
  let prefix='vim'
  let dir_list={
    \ 'backup': 'backupdir',
    \ 'views': 'viewdir',
    \ 'swap': 'directory'}

  if has('persistent_undo')
    let dir_list['undo']='undodir'
  endif

  let common_dir=parent . '/.' . prefix

  for [dirname, settingname] in items(dir_list)
    let directory=common_dir . '/' . dirname . '/'
    if exists("*mkdir")
      if !isdirectory(directory)
        call mkdir(directory)
      endif
    endif
    if !isdirectory(directory)
      echo "Warning: Unable to create backup directory: " . directory
      echo "Try: mkdir -p " . directory
    else
      let directory=substitute(directory, " ", "\\\\ ", "g")
      exec "set " . settingname . "=" . directory
    endif
  endfor
endfunction
call InitializeDirectories()





"-------------Basics--------------"

" Encoding
set encoding=utf-8

" Mouse
set mouse=a
set mousehide

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

" OSX copy/paste
set clipboard=unnamedplus,unnamed,autoselect





"-------------Visuals--------------"

" Color settings
set background=dark
set t_CO=256
let base16colorspace=256
colorscheme base16-eighties

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
set pastetoggle=<F12>

" Wrapped lines go down/up to next row, rather than next line in file.
noremap j gj
noremap k gk

" Easier moving in tabs and windows
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l
map <C-h> <C-w>h

" Quick vimrc edit
nmap <leader>ev :tabedit $MYVIMRC<cr>

" Easier escape
inoremap jk <Esc>

" Easier colon
nnoremap ; :
vnoremap ; :
nnoremap ;; ;
vnoremap ;; ;

" Easier save
inoremap <C-s> <C-o>:update<cr>
nnoremap <C-s> :update<cr>

" Easier quit
inoremap <C-q> <esc>:q<cr>
nnoremap <C-q> :q<cr>
vnoremap <C-q> <esc>:q<cr>




"-------------Plugin Settings--------------"

" Airline
let g:airline_theme='base16'
let g:airline_powerline_fonts=1
set laststatus=2

" Better whitespace
let g:strip_whitespace_on_save=1

" Indent guides
let g:indent_guides_enable_on_vim_startup=1
let g:indent_guides_auto_colors=0
autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd   ctermbg=00
autocmd VimEnter,Colorscheme * :hi IndentGuidesEven  ctermbg=18

" FZF
nnoremap <silent> <expr> <Leader>p (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":FZF\<cr>"
nnoremap <silent> <expr> <Leader>b (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Buffers\<cr>"
nnoremap <silent> <expr> <Leader>r (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":BTags\<cr>"
"nnoremap <silent> <expr> <Leader>f (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Tags\<cr>"
nnoremap <silent> <expr> <Leader>h (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":History\<cr>"

" Nerd Tree
nnoremap <leader>kb :NERDTreeToggle<cr>
let g:NERDTreeHijackNetrw=0

" Multi Cursor
let g:multi_cursor_insert_maps={ 'j':1 }





"-------------Auto-Commands--------------"

" Source the vimrc file on save.
augroup autosourcing
  autocmd!
  autocmd BufWritePost .vimrc source %
augroup END

" Retab on save
augroup autoretab
  autocmd!
  autocmd BufWrite *.py %retab
augroup END
