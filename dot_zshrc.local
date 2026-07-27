# WSL-specific additions kept outside the shared zsh baseline.

# Preserve terminal metadata for SSH connections to the Arch host.
export COLORTERM="${COLORTERM:-truecolor}"
export TERM_PROGRAM="${TERM_PROGRAM:-xterm-256}"

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

function piu() {
  command mise upgrade 'npm:@earendil-works/pi-coding-agent' --minimum-release-age 0s
}

# Launch the Windows-hosted PoE2 intelligence app from its project directory.
export POE2="/mnt/c/Users/Jeff Hertzler/Documents/poe2-item-intelligence"

function poe2() {
  (
    cd "$POE2" || exit 1
    command python.exe -m poe2_intel.server_control "$@"
  )
}

# Herdr remote entry points. The local `h` alias comes from common.sh.
function ha() {
  command herdr --remote arch --remote-keybindings server "$@"
}

function hat() {
  command herdr --remote archt --remote-keybindings server "$@"
}

function hatw() {
  command herdr --remote archt --session work --remote-keybindings server "$@"
}

function hatv() {
  command herdr --remote archt --session vimme --remote-keybindings server "$@"
}
