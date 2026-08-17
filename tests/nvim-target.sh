#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nvim-target-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/runtime/herdr-nvim"

cat >"$tmp/bin/nvim" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_NVIM_LOG"
[[ $* == *'/run/user/1000/nvim.sibling.0'* ]] || exit 1
if [[ $* == *'v:servername'* ]]; then
  printf '%s\n' '/run/user/1000/nvim.sibling.0'
else
  printf '%s\n' '{"ok":true,"schemaVersion":1,"comments":[]}'
fi
EOF

cat >"$tmp/bin/herdr" <<'EOF'
#!/usr/bin/env bash
[[ $* == 'pane list --workspace w0' ]] || exit 2
cat <<'JSON'
{"result":{"panes":[
  {"pane_id":"w0:p1","tab_id":"w0:t1","workspace_id":"w0"},
  {"pane_id":"w0:p2","tab_id":"w0:t1","workspace_id":"w0"}
]}}
JSON
EOF

chmod +x "$tmp/bin/nvim" "$tmp/bin/herdr"
printf '%s\n' '/run/user/1000/nvim.sibling.0' >"$tmp/runtime/herdr-nvim/w0_p2.server"

export PATH="$tmp/bin:$PATH"
export XDG_RUNTIME_DIR="$tmp/runtime"
export MOCK_NVIM_LOG="$tmp/nvim.log"
export HERDR_ENV=1
export HERDR_PANE_ID='w0:p1'
export HERDR_TAB_ID='w0:t1'
export HERDR_WORKSPACE_ID='w0'
unset NVIM HERDR_ACTIVE_PANE_ID TMUX || true

# shellcheck source=../dot_local/lib/nvim-target.sh
source "$repo_root/dot_local/lib/nvim-target.sh"

if ! nvim_target_resolve; then
  printf 'expected resolver to find the unique live Neovim server in a sibling Herdr pane\n' >&2
  exit 1
fi

[[ $NVIM_TARGET_SERVER == '/run/user/1000/nvim.sibling.0' ]]
[[ $NVIM_TARGET_LAUNCHER == 'herdr_workspace' ]]

mkdir -p "$tmp/home/.local/lib"
cp "$repo_root/dot_local/lib/nvim-target.sh" "$tmp/home/.local/lib/nvim-target.sh"
response=$(HOME="$tmp/home" bash "$repo_root/dot_local/bin/executable_agent-review" list)
printf '%s' "$response" | jq -e '.ok == true and .comments == []' >/dev/null
grep -F -- '--server /run/user/1000/nvim.sibling.0 --remote-expr' "$MOCK_NVIM_LOG" >/dev/null

printf 'nvim-target sibling-pane discovery passed\n'
