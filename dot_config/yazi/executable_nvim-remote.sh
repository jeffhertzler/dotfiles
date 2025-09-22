#!/bin/bash

# This script opens files in an existing neovim instance or falls back to a new one
# It's designed to work with yazi in a tmux split

# Function to find nvim socket
find_nvim_socket() {
  # If NVIM environment variable is set, use it
  if [ -n "$NVIM" ]; then
    echo "$NVIM"
    return
  fi

  # Try to find nvim socket in common locations
  local socket_dirs="/tmp /run/user/$(id -u)"
  for dir in $socket_dirs; do
    if [ -d "$dir" ]; then
      # Look for nvim socket files
      local socket=$(find "$dir" -name "nvim.*" -type s 2>/dev/null | head -1)
      if [ -n "$socket" ]; then
        echo "$socket"
        return
      fi
    fi
  done
}

# Try to find and use nvim socket
NVIM_SOCKET=$(find_nvim_socket)

if [ -n "$NVIM_SOCKET" ]; then
  # Try to connect to existing nvim instance
  nvim --server "$NVIM_SOCKET" --remote "$@" 2>/dev/null
  status=$?

  # If successful, exit
  if [ $status -eq 0 ]; then
    exit 0
  fi
fi

# Fallback to regular nvim if server connection fails
exec nvim "$@"
