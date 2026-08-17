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

nvim_target_resolve_herdr_workspace() {
  [ -n "${HERDR_WORKSPACE_ID:-}" ] || return 1
  command -v herdr >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  nvim_target_panes=$(herdr pane list --workspace "$HERDR_WORKSPACE_ID" 2>/dev/null) || return 1
  nvim_target_panes=$(printf '%s' "$nvim_target_panes" | jq -r '
    (.result.panes // [])[]
    | select(.pane_id != null)
    | [.pane_id, (.tab_id // "")]
    | @tsv
  ' 2>/dev/null) || return 1

  nvim_target_registry_dir=$(nvim_target_registry_directory)
  nvim_target_same_tab_servers=
  nvim_target_workspace_servers=
  while IFS="$(printf '\t')" read -r nvim_target_sibling_pane nvim_target_sibling_tab; do
    [ -n "$nvim_target_sibling_pane" ] || continue
    nvim_target_safe_pane=$(printf '%s' "$nvim_target_sibling_pane" | tr -c 'A-Za-z0-9_.-' '_')
    nvim_target_registry_file=$nvim_target_registry_dir/$nvim_target_safe_pane.server
    [ -r "$nvim_target_registry_file" ] || continue

    IFS= read -r nvim_target_candidate <"$nvim_target_registry_file" || nvim_target_candidate=
    if ! nvim_target_live "$nvim_target_candidate"; then
      rm -f "$nvim_target_registry_file"
      continue
    fi

    nvim_target_workspace_servers="${nvim_target_workspace_servers}${nvim_target_candidate}
"
    if [ -n "${HERDR_TAB_ID:-}" ] && [ "$nvim_target_sibling_tab" = "$HERDR_TAB_ID" ]; then
      nvim_target_same_tab_servers="${nvim_target_same_tab_servers}${nvim_target_candidate}
"
    fi
  done <<EOF
$nvim_target_panes
EOF

  nvim_target_same_tab_servers=$(printf '%s' "$nvim_target_same_tab_servers" | awk 'NF && !seen[$0]++')
  nvim_target_candidate_count=$(printf '%s\n' "$nvim_target_same_tab_servers" | awk 'NF { count++ } END { print count + 0 }')
  if [ "$nvim_target_candidate_count" -eq 1 ]; then
    NVIM_TARGET_SERVER=$nvim_target_same_tab_servers
    NVIM_TARGET_LAUNCHER=herdr_workspace
    return 0
  fi
  [ "$nvim_target_candidate_count" -eq 0 ] || return 1

  nvim_target_workspace_servers=$(printf '%s' "$nvim_target_workspace_servers" | awk 'NF && !seen[$0]++')
  nvim_target_candidate_count=$(printf '%s\n' "$nvim_target_workspace_servers" | awk 'NF { count++ } END { print count + 0 }')
  [ "$nvim_target_candidate_count" -eq 1 ] || return 1

  NVIM_TARGET_SERVER=$nvim_target_workspace_servers
  NVIM_TARGET_LAUNCHER=herdr_workspace
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
  nvim_target_resolve_herdr_workspace && return 0
  nvim_target_resolve_tmux && return 0
  return 1
}
