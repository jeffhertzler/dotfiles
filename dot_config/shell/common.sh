# Shared interactive behavior for Bash and Zsh.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export VISUAL="nvim"
export EDITOR="nvim"
export GIT_EDITOR="nvim"

[ ! -r "$HOME/.config/shell/opencode.sh" ] || . "$HOME/.config/shell/opencode.sh"

alias h='herdr'
alias lag='lazygit'
alias v='nvim .'
alias vi='nvim'
alias vim='nvim'
alias vimdiff='nvim -d'

alias cm='chezmoi'
alias rmrf='rm -rf'

alias gb='git branch'
alias gbd='git branch -D'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gcod='git checkout develop'
alias gcom='git checkout main'
alias gc='git commit'
alias gci="git commit --allow-empty -m 'ci: bump'"
alias gcm='git commit -m'
alias gcp='git cherry-pick'
alias gl='git pull'
alias gp='git push'

function piu() {
  if command -v mise >/dev/null 2>&1; then
    command mise upgrade 'npm:@earendil-works/pi-coding-agent' --minimum-release-age 0s
  elif command -v volta >/dev/null 2>&1; then
    command volta install @earendil-works/pi-coding-agent@latest
  else
    printf '%s\n' 'piu: neither mise nor volta is available' >&2
    return 127
  fi
}

function rcu() {
  if command -v rustup >/dev/null 2>&1; then
    command rustup update
  fi
  if command -v cargo-install-update >/dev/null 2>&1; then
    command cargo install-update --all
  fi
}

if command -v uv >/dev/null 2>&1; then
  alias uvu='uv tool upgrade --all'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat'
fi

if command -v lazydocker >/dev/null 2>&1; then
  alias lad='lazydocker'
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza'
  alias la='eza -laag --icons'
  alias lt='eza -T --icons'
fi

if command -v posting >/dev/null 2>&1; then
  alias pe='nvim ~/.local/share/posting/default'
fi

if command -v cursor-agent >/dev/null 2>&1; then
  alias ca='cursor-agent --yolo'
fi

if command -v yazi >/dev/null 2>&1; then
  function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  }
fi

# WSL and the Arch host use the upstream Linux x86_64 AppImage.
if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
  function nvu() {
    local tmp exit_code
    tmp="$(mktemp)" || return 1

    command curl -fL \
      "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage" \
      -o "$tmp" &&
      mkdir -p "$HOME/.local/bin" &&
      command install -m 755 "$tmp" "$HOME/.local/bin/nvim"
    exit_code=$?

    rm -f "$tmp"
    return "$exit_code"
  }
fi
