#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/agent-diff-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local repo=$1
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'local old_name = 1\nkeep\n' >"$repo/sample.lua"
  printf 'second old\n' >"$repo/second.txt"
  git -C "$repo" add sample.lua second.txt
  git -C "$repo" commit -qm initial
  printf 'local new_name = 2\nkeep\nadded\n' >"$repo/sample.lua"
  printf 'second new\n' >"$repo/second.txt"
}

for case in lifecycle gitsigns neogit revisions patch large_diff; do
  repo="$tmp/$case"
  make_repo "$repo"
  (
    cd "$repo"
    AGENT_DIFF_PLUGIN_ROOT="$root" \
    AGENT_DIFF_TEST_CASE="$root/tests/cases/$case.lua" \
    AGENT_DIFF_TEST_FILE="$repo/sample.lua" \
      timeout 30s nvim --headless -i NONE -u "$root/tests/minimal_init.lua" \
        "+lua dofile([[$root/tests/harness.lua]])"
  )
done

printf '\nAll agent-diff tests passed.\n'
