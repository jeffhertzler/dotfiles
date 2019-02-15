function dark
  eval sh $HOME/.config/base16-shell/scripts/base16-dracula.sh
end
function light
  eval sh $HOME/.config/base16-shell/scripts/base16-harmonic16-light.sh
end

set fish_greeting
set SPACEFISH_NODE_DEFAULT_VERSION "0.0.0"
set SPACEFISH_PACKAGE_SHOW false

if test "$TERM" != "eterm-color"
  and test "$TERM" != "dumb"
  fish_vi_key_bindings
  bind -M insert \cj down-or-search
  bind -M insert \ck up-or-search
end

set -x EDITOR e
set -x GIT_EDITOR vim

source $HOME/.asdf/asdf.fish

function asdf --wrap asdf
  command asdf $argv
  set passed $status
  if test $passed -eq 0
   set longver (command asdf current java 2>&1)
   set ver (string replace -r " *\(set by.*\)" "" $longver)
   if test "$ver" != "$longver"
    set -U JAVA_HOME (command asdf where java $ver)
   else
    set -U JAVA_HOME
   end
   true
  else
   false
  end
end

# set -x GOPATH $HOME/dev/go
# set -x GOBIN $GOPATH/bin

# set -x PATH $JAVA_HOME/Contents/Home/bin $HOME/bin $GOBIN $PATH
# set -x PATH $HOME/bin $PATH

# set -x COMPOSER_DISABLE_XDEBUG_WARN 1

# set -x FZF_DEFAULT_COMMAND 'rg --files --hidden --glob "!.git" ^ /dev/null'
# set -x FZF_FIND_FILE_COMMAND $FZF_DEFAULT_COMMAND

alias vi vim

if type nvim > /dev/null ^ /dev/null
  alias vi nvim
  alias vim nvim
end

function e --wraps /Applications/Emacs.app/Contents/MacOS/Emacs
  bash -c 'emacsclient -na /Applications/Emacs.app/Contents/MacOS/Emacs $@ >/dev/null 2>&1' _ $argv &
end

# abbr art "php artisan"
abbr fe "e ~/.config/fish/config.fish"
abbr se "e ~/.spacemacs.d/init.el"
# abbr ze "e ~/.zshrc"
abbr ve "vim ~/.vimrc"

abbr gco "git checkout"
abbr gcm "git checkout master"
abbr gcd "git checkout develop"
abbr gcl "git checkout 2018.7.3"
abbr gl "git pull"
abbr gp "git push"
abbr gcmsg "git commit -m"
abbr gaa "git add --all"
abbr gs "git status"
abbr gb "git branch"
abbr gbd "git branch -D"
abbr gmd "git merge develop"

alias glg "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset %C(cyan)[%G?]%Creset' --abbrev-commit"
alias glgs "git log --show-signature"

# abbr ci "composer install"
# abbr cu "composer update"
# abbr cgo "composer global outdated"
# abbr cgu "composer global update"

abbr cdgc "cd ~/dev/greenlight/client"
abbr cdsg "cd ~/dev/greenlight/style-guide"
abbr cdgg "cd ~/dev/greenlight/gg"
abbr cdgs "cd ~/dev/greenlight/server"

alias bubu "brew update; and brew upgrade; and brew cleanup"
alias bcu "brew cask brew upgrade"

# alias cbundle "bundle _1.12.5_"
alias code "code-insiders"

# function pt --wraps phpunit
#   if test -e vendor/bin/phpunit
#     vendor/bin/phpunit $argv
#   else
#     phpunit $argv
#   end
# end
alias ptf "pt --filter"

if status --is-interactive
  if test "$TERM" != "eterm-color"
    and test "$TERM" != "dumb"
    eval sh $HOME/.config/base16-shell/scripts/base16-dracula.sh
  end
  if test "$TERM_PROGRAM" = "iTerm.app"
    echo -e "\033]6;1;bg;red;brightness;40\a"
    echo -e "\033]6;1;bg;green;brightness;41\a"
    echo -e "\033]6;1;bg;blue;brightness;54\a"
    clear
  end
end
