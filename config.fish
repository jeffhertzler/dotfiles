if test ! -e $HOME/.config/fish/functions/fisher.fish
  curl -Lo $HOME/.config/fish/functions/fisher.fish --create-dirs git.io/fisher
end

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
  segment white 515151 " $pwd "
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
  segment_right white 515151 " $time "
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

fish_vi_key_bindings

if test ! -d $HOME/bin
  mkdir $HOME/bin
end

if test ! -e $HOME/.asdf/asdf.fish
  echo "Installing asdf";
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf
end

source $HOME/.asdf/asdf.fish

set -x GOPATH $HOME/dev/go
set -x PATH $HOME/bin $GOPATH/bin /usr/local/sbin $PATH

set -x COMPOSER_DISABLE_XDEBUG_WARN 1

alias vi vim
set -x EDITOR vim

if type nvim >/dev/null 2>/dev/null
  alias vi nvim
  alias vim nvim
  set -x EDITOR nvim
end

alias art "php artisan"
alias fe "vim ~/.config/fish/config.fish"
alias se "vim ~/.spacemacs.d/init.el"
alias ze "vim ~/.zshrc"
alias ve "vim ~/.vimrc"

alias gco "git checkout"
alias gcm "git checkout master"
alias gl "git pull"
alias gp "git push"
alias gcmsg "git commit -m"
alias gaa "git add --all"

alias bubu "brew update; and brew upgrade; and brew cleanup"

alias cbundle "bundle _1.12.5_"

if test ! -e $HOME/.config/base16-shell/scripts/base16-eighties.sh
  echo "Installing base16-shell";
  git clone https://github.com/chriskempson/base16-shell.git ~/.config/base16-shell
end

if status --is-interactive
  eval sh $HOME/.config/base16-shell/scripts/base16-eighties.sh
end
