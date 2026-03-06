#!/bin/sh

NVIM_SOCKET=$(~/.local/bin/tmux-nvim-server 2>/dev/null)

if [ -n "$NVIM_SOCKET" ]; then
  nvim --server "$NVIM_SOCKET" --remote "$@" 2>/dev/null
  status=$?

  if [ "$status" -eq 0 ]; then
    exit 0
  fi
fi

exec nvim "$@"
