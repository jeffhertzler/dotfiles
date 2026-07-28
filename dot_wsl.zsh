# WSL-specific additions kept outside the shared zsh baseline.

# Preserve terminal metadata for SSH connections to the Arch host.
export COLORTERM="${COLORTERM:-truecolor}"
export TERM_PROGRAM="${TERM_PROGRAM:-xterm-256}"

# Do not let Mise discover the native Windows global config while traversing
# upward from projects under the mounted Windows home.
export MISE_CEILING_PATHS="$HOME:/mnt/c/Users/Jeff Hertzler"

# Launch the Windows-hosted PoE2 intelligence app from its project directory.
export POE2="/mnt/c/Users/Jeff Hertzler/Documents/poe2-item-intelligence"

function poe2() {
  (
    cd "$POE2" || exit 1
    command python.exe -m poe2_intel.server_control "$@"
  )
}

function hatw() {
  command herdr --remote archt --session work --remote-keybindings server "$@"
}

function hatv() {
  command herdr --remote archt --session vimme --remote-keybindings server "$@"
}
