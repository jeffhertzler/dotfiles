#!/usr/bin/env zsh

alias tu="tmux-preview-update"

# Arch-only legacy tmux and Workmux integration.
alias ta="tmux a"
alias te="nvim ~/.local/share/chezmoi/dot_config/tmux/tmux.conf"
alias wm='workmux'

# Arch owns the active Tailscale service controls.
alias tsd="sudo tailscale down"
alias tsu="sudo tailscale up --accept-dns --accept-routes"

if command -v workmux >/dev/null 2>&1; then
	eval "$(workmux completions zsh)"
fi
