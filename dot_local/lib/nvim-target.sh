# Shared lookup for tools that need to return to their originating Neovim.

nvim_target_live() {
  [ -n "$1" ] && nvim --headless --server "$1" --remote-expr 'v:servername' >/dev/null 2>&1
}

nvim_target_registry_directory() {
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    printf '%s\n' "$XDG_RUNTIME_DIR/herdr-nvim"
  elif [ "${OS:-}" = Windows_NT ]; then
    printf '%s\n' "${TMPDIR:-/tmp}/herdr-nvim"
  else
    printf '%s\n' "/tmp/herdr-nvim-$(id -u)"
  fi
}

nvim_target_resolve_herdr() {
  nvim_target_pane=${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}
  [ -n "$nvim_target_pane" ] || return 1

  nvim_target_registry_dir=$(nvim_target_registry_directory)
  nvim_target_safe_pane=$(printf '%s' "$nvim_target_pane" | tr -c 'A-Za-z0-9_.-' '_')
  nvim_target_registry_file=$nvim_target_registry_dir/$nvim_target_safe_pane.server
  [ -r "$nvim_target_registry_file" ] || return 1

  IFS= read -r nvim_target_candidate <"$nvim_target_registry_file" || nvim_target_candidate=
  if nvim_target_live "$nvim_target_candidate"; then
    NVIM_TARGET_SERVER=$nvim_target_candidate
    NVIM_TARGET_LAUNCHER=herdr_popup
    return 0
  fi

  rm -f "$nvim_target_registry_file"
  return 1
}

nvim_target_resolve_tmux() {
  nvim_target_candidate=$("$HOME/.local/bin/tmux-nvim-server" 2>/dev/null) || nvim_target_candidate=
  nvim_target_live "$nvim_target_candidate" || return 1

  NVIM_TARGET_SERVER=$nvim_target_candidate
  NVIM_TARGET_LAUNCHER=tmux_popup
}

nvim_target_resolve() {
  NVIM_TARGET_SERVER=
  NVIM_TARGET_LAUNCHER=standalone

  if nvim_target_live "${NVIM:-}"; then
    NVIM_TARGET_SERVER=$NVIM
    NVIM_TARGET_LAUNCHER=nvim_terminal
    return 0
  fi

  nvim_target_resolve_herdr && return 0
  nvim_target_resolve_tmux && return 0
  return 1
}
