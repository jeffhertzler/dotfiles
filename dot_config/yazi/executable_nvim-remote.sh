#!/bin/sh

quit_yazi() {
  if [ -n "$YAZI_ID" ] && command -v ya >/dev/null 2>&1; then
    (
      sleep 0.2
      ya emit quit >/dev/null 2>&1 || true
    ) >/dev/null 2>&1 &
  fi
}

NVIM_SOCKET=$(~/.local/bin/tmux-nvim-server 2>/dev/null)

if [ -n "$NVIM_SOCKET" ]; then
  nvim --server "$NVIM_SOCKET" --remote "$@" 2>/dev/null
  status=$?

  if [ "$status" -eq 0 ]; then
    quit_yazi
    exit 0
  fi
fi

quit_yazi
exec nvim "$@"
