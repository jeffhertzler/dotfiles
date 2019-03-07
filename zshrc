#!/usr/bin/env zsh

if [ ! -r ~/.zplug/init.zsh ]; then
  echo "Installing zplug to ~/.zplug";
  git clone https://github.com/chriskjaer/zplug ~/.zplug
fi;
source ~/.zplug/init.zsh

zplug "zplug/zplug", hook-build:"zplug --self-manage"
zplug "chriskempson/base16-shell"
zplug "denysdovhan/spaceship-prompt", as:theme
zplug "momo-lab/zsh-abbrev-alias"
zplug "peterhurford/up.zsh"
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-syntax-highlighting", defer:2
zplug "zsh-users/zsh-history-substring-search", defer:2

# Install plugins if there are plugins that have not been installed
if ! zplug check; then
  zplug install
fi

zplug load

# bindkey -v
spaceship_vi_mode_enable

dark() {
  base16_dracula
}
light() {
  base16_harmonic-light
}

e() {
  emacsclient -na /Applications/Emacs.app/Contents/MacOS/Emacs $@ >/dev/null 2>&1 &
}

bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

bindkey '^F' autosuggest-accept
bindkey -M vicmd '^F' autosuggest-accept

bindkey -M viins " " __abbrev_alias::magic_abbrev_expand

if type nvim >/dev/null 2>&1; then
  alias vi=nvim
  alias vim=nvim
fi

abbrev-alias -c ve="vim ~/.vimrc"
abbrev-alias -c ze="e ~/.zshrc"

abbrev-alias -c gco="git checkout"
abbrev-alias -c gcm="git checkout master"
abbrev-alias -c gcd="git checkout develop"
abbrev-alias -c gcl="git checkout 2019.1.0"
abbrev-alias -c gl="git pull"
abbrev-alias -c gp="git push"
abbrev-alias -c gpf="git push --force"
abbrev-alias -c gcmsg="git commit -m"
abbrev-alias -c gaa="git add --all"
abbrev-alias -c gs="git status"
abbrev-alias -c gb="git branch"
abbrev-alias -c gbd="git branch -D"
abbrev-alias -c gmd="git merge develop"

alias glg="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset %C(cyan)[%G?]%Creset' --abbrev-commit"
alias glgs="git log --show-signature"

abbrev-alias -c cdgc="cd ~/dev/greenlight/client"
abbrev-alias -c cdsg="cd ~/dev/greenlight/style-guide"
abbrev-alias -c cdgg="cd ~/dev/greenlight/gg"
abbrev-alias -c cdgs="cd ~/dev/greenlight/server"

alias bubu="brew update; and brew upgrade; and brew cleanup"

alias code="code-insiders"

export EDITOR=e
export GIT_EDITOR=e

# export COMPOSER_DISABLE_XDEBUG_WARN=1

# abbrev-alias -c ci="composer install"
# abbrev-alias -c cu="composer update"
# abbrev-alias -c cgo="composer global outdated"
# abbrev-alias -c cgu="composer global update"

# # allow usage of C-q and C-s shortcuts other places
# stty -ixon
# stty start undef
# stty stop undef
