function jh_untracked_files
  if not git_is_repo
    return 0
  end

  command git ls-files --others --exclude-standard | awk '
    // {
      z++
      exit 0
    }
    END {
      exit !z
    }
  '
end

function jh_prompt_pwd
  set pwd (prompt_pwd)
  segment black white " $pwd "
end

function jh_prompt_mode
  if test "$fish_key_bindings" = "fish_vi_key_bindings"
    or test "$fish_key_bindings" = "fish_hybrid_key_bindings"
    switch $fish_bind_mode
      case default
        segment yellow black 'Ⓝ  '
      case insert
        segment green black 'Ⓘ  '
      case replace-one
        segment brred black 'Ⓡ  '
      case visual
        segment white black 'Ⓥ  '
    end
  end
end

function jh_prompt_time
  set time (date +%r)
  segment_right black white " $time "
end

function jh_prompt_status
  if [ $last_status -eq 0 ]
    segment_right green black " ✔"
  else
    segment_right red black " ✘"
  end
end

function jh_prompt_git
  if git_is_repo
    set color green
    set ahead (git_ahead " ↑" " ↓" " ⇵")
    set branch (git_branch_name)
    set branch_icon \uE0A0
    set icons ""
    set stashed ""
    if git_is_stashed
      set stashed " ⍟"
    end
    if jh_untracked_files
      set color magenta
      set icons $icons" ?"
    end
    if git_is_dirty
      set color yellow
      set icons $icons" ●"
    end
    if git_is_staged
      set icons $icons" ✚"
      if not git_is_dirty
        set color cyan
      end
    end
    if git_is_detached_head
      set branch_icon ↜
      set color red
    end
    segment_right black $color "$stashed$ahead$icons $branch $branch_icon "
  end
end

function fish_mode_prompt
end

function fish_prompt
  printf "\u2016 "
  jh_prompt_pwd
  jh_prompt_mode
  segment_close
  printf "\n\u2016 "
end

function fish_right_prompt
  set -g last_status $status
  tput sc; tput cuu1; tput cuf 2
  jh_prompt_git
  jh_prompt_time
  jh_prompt_status
  segment_close
  tput rc
end

function dark
  eval sh $HOME/.config/base16-shell/scripts/base16-dracula.sh
end
function light
  eval sh $HOME/.config/base16-shell/scripts/base16-harmonic16-light.sh
end

fish_vi_key_bindings

source $HOME/.asdf/asdf.fish

set -x GOPATH $HOME/dev/go
set -x ANDROID_HOME $HOME/Library/Android/sdk

set -x PATH $ANDROID_HOME/tools $ANDROID_HOME/platform-tools $HOME/.fastlane/bin $HOME/bin $GOPATH/bin /usr/local/sbin $PATH

set -x COMPOSER_DISABLE_XDEBUG_WARN 1

set -x FZF_DEFAULT_COMMAND 'rg --files --hidden --glob "!.git" ^ /dev/null'
set -x FZF_FIND_FILE_COMMAND $FZF_DEFAULT_COMMAND

alias vi vim

if type nvim > /dev/null ^ /dev/null
  alias vi nvim
  alias vim nvim
end

function e --wraps emacs
  bash -c 'emacsclient -n -a emacs "$@" >/dev/null 2>&1 &' _ $argv
end

set -x EDITOR e

alias art "php artisan"
alias fe "e ~/.config/fish/config.fish"
alias se "e ~/.spacemacs.d/init.el"
alias ze "e ~/.zshrc"
alias ve "vim ~/.vimrc"

alias gco "git checkout"
alias gcm "git checkout master"
alias gl "git pull"
alias gp "git push"
alias gcmsg "git commit -m"
alias gaa "git add --all"
alias gs "git status"
alias glg "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset %C(cyan)[%G?]%Creset' --abbrev-commit"
alias glgs "git log --show-signature"

alias ci "composer install"
alias cu "composer update"
alias cgo "composer global outdated"
alias cgu "composer global update"

alias bubu "brew update; and brew upgrade; and brew cleanup"

alias cbundle "bundle _1.12.5_"

function pt --wraps phpunit
  if test -e vendor/bin/phpunit
    vendor/bin/phpunit $argv
  else
    phpunit $argv
  end
end
alias ptf "pt --filter"

if status --is-interactive
  eval sh $HOME/.config/base16-shell/scripts/base16-dracula.sh
end
