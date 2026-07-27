#!/usr/bin/env zsh

# alias nvu="yay -S neovim-nightly --answerclean None --answerdiff None --answeredit None --answerupgrade None --noconfirm"
function nvu() {
	local tmp
	tmp="$(mktemp)" || return 1
	curl -fL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage" -o "$tmp" &&
	mkdir -p ~/.local/bin &&
	install -m 755 "$tmp" ~/.local/bin/nvim
	local exit_code=$?
	rm -f "$tmp"
	return $exit_code
}
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
