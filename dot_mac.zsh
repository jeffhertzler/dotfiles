alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
alias bubu="brew update; brew upgrade; brew cleanup"

export K9S_CONFIG_DIR="$HOME/.config/k9s"
alias k9s='TERM=xterm-ghostty k9s'
alias ca="agent --yolo"

# Herdr remote entry points for the Arch host. SSH decides whether each host
# uses the direct, Tailscale, or explicitly remote route.
function ha() {
  command herdr --remote arch --remote-keybindings server "$@"
}

function hat() {
  command herdr --remote archt --remote-keybindings server "$@"
}
