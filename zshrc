export TERM="xterm-256color"

# Download antigen with git if it doesn't exist already
if [ ! -r ~/.antigen/antigen.zsh ]; then
  [ ! command -v git > /dev/null 2>&1 ] ||
    (echo "Please install git." &&
    return;)
  echo "Installing antigen into ~/.antigen/";
  git clone https://github.com/zsh-users/antigen.git ~/.antigen
fi;

if [ ! -r ~/.config/base16-shell/scripts/base16-eighties.sh ]; then
  [ ! command -v git > /dev/null 2>&1 ] ||
    (echo "Please install git." &&
    return;)
  echo "Installing base16-shell into ~/.config/base16-shell";
  git clone https://github.com/chriskempson/base16-shell.git ~/.config/base16-shell
fi;

if [ ! -r ~/.iterm2_shell_integration.zsh ]; then
  curl -L https://iterm2.com/misc/zsh_startup.in >> \
  ~/.iterm2_shell_integration.zsh
  source ~/.iterm2_shell_integration.zsh
fi;

source $HOME/.antigen/antigen.zsh

# prompt configs
export PROMPT_ON_NEWLINE=true
export ZLE_RPROMPT_INDENT=0

# allow usage of C-q and C-s shortcuts other places
stty -ixon
stty start undef
stty stop undef

# fix for iterm c-h issue
# infocmp $TERM | sed 's/kbs=^[hH]/kbs=\\177/' > $HOME/.terminfo/$TERM.ti
# tic $HOME/.terminfo/$TERM.ti

antigen use oh-my-zsh

if [[ "$OSTYPE" == "darwin"* ]]; then
  antigen bundle brew
  antigen bundle osx
fi
antigen bundle composer
antigen bundle docker
antigen bundle docker-compose
antigen bundle extract
antigen bundle git
antigen bundle git-extras
antigen bundle vagrant
antigen bundle wp-cli
antigen bundle chruby
antigen bundle nvm
antigen bundle zsh-users/zsh-syntax-highlighting

if [ -n "$INSIDE_EMACS" ]; then
  antigen theme clean
else
  POWERLEVEL9K_PROMPT_ON_NEWLINE=true
  POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX="|"
  POWERLEVEL9K_MULTILINE_SECOND_PROMPT_PREFIX="|  "
  POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(vi_mode context dir vcs)
  POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status time battery)
  POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
  POWERLEVEL9K_SHORTEN_DELIMITER=""
  POWERLEVEL9K_SHORTEN_STRATEGY="truncate_from_right"
  POWERLEVEL9K_TIME_FORMAT="%D{%r}"
  POWERLEVEL9K_CONTEXT_DEFAULT_FOREGROUND="white"
  antigen theme bhilburn/powerlevel9k powerlevel9k
fi

antigen apply

which -s brew >> /dev/null
if [ $? = 0 ]
  then
    export PATH="$(brew --prefix homebrew/php/php70)"/bin:/usr/local/sbin:/usr/local/bin:$PATH
fi

export COMPOSER_DISABLE_XDEBUG_WARN=1

alias vi=vim
export EDITOR=vim

if type nvim >/dev/null 2>/dev/null; then
  alias vi=nvim
  alias vim=nvim
  export EDITOR=nvim
fi

BASE16_SHELL="$HOME/.config/base16-shell/scripts/base16-eighties.sh"

if [ -z "$INSIDE_EMACS" ]; then
  [[ -s $BASE16_SHELL ]] && source $BASE16_SHELL
fi

alias art='php artisan'
alias vsync='vagrant gatling-rsync-auto local'
alias gfs='git stash -u && git pull && git stash drop'
alias reload=". ~/.zshrc && echo 'ZSH config reloaded from ~/.zshrc'"
alias ze="vim ~/.zshrc && reload"
alias ve="vim ~/.vimrc"

if [[ "$OSTYPE" == "darwin"* ]]; then
  alias code=code-insiders
else
  setxkbmap -layout us -option ctrl:nocaps
  eval $(ssh-agent)
  ssh-add
fi

export FZF_DEFAULT_COMMAND='(git ls-files && git ls-files -o --exclude-standard || ag -g "") 2> /dev/null'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

export NVM_DIR="/Users/pete/.nvm"
