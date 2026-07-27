#!/bin/sh

quit_yazi() {
  if [ -n "$YAZI_ID" ] && command -v ya >/dev/null 2>&1; then
    (
      sleep 0.2
      ya emit quit >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
  fi
}

live_nvim_server() {
  [ -n "$1" ] && nvim --server "$1" --remote-expr 'v:servername' >/dev/null 2>&1
}

NVIM_SOCKET=${NVIM:-}
if ! live_nvim_server "$NVIM_SOCKET"; then
  NVIM_SOCKET=
fi

if [ -z "$NVIM_SOCKET" ]; then
  herdr_pane=${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}
  if [ -n "$herdr_pane" ]; then
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
      registry_dir=$XDG_RUNTIME_DIR/herdr-nvim
    elif [ "${OS:-}" = Windows_NT ]; then
      registry_dir=${TMPDIR:-/tmp}/herdr-nvim
    else
      registry_dir=/tmp/herdr-nvim-$(id -u)
    fi
    safe_pane=$(printf '%s' "$herdr_pane" | tr -c 'A-Za-z0-9_.-' '_')
    registry_file=$registry_dir/$safe_pane.server

    if [ -r "$registry_file" ]; then
      IFS= read -r candidate <"$registry_file" || candidate=
      if live_nvim_server "$candidate"; then
        NVIM_SOCKET=$candidate
      else
        rm -f "$registry_file"
      fi
    fi
  fi
fi

if [ -z "$NVIM_SOCKET" ]; then
  candidate=$(~/.local/bin/tmux-nvim-server 2>/dev/null) || candidate=
  if live_nvim_server "$candidate"; then
    NVIM_SOCKET=$candidate
  fi
fi

if [ -n "$NVIM_SOCKET" ] && nvim --server "$NVIM_SOCKET" --remote "$@" 2>/dev/null; then
  quit_yazi
  exit 0
fi

quit_yazi
exec nvim "$@"
