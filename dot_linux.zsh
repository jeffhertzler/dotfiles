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

