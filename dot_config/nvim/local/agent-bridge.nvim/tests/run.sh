#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/agent-bridge-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

run_case() {
  local name=$1
  local file="$tmp/$name.lua"
  printf 'header\nlocal value = 200\ntarget line\nfooter\n' >"$file"

  AGENT_BRIDGE_PLUGIN_ROOT="$root" \
  AGENT_BRIDGE_TEST_CASE="$root/tests/cases/$name.lua" \
  AGENT_BRIDGE_TEST_FILE="$file" \
    timeout 20s nvim --headless -i NONE -u "$root/tests/minimal_init.lua" \
      "+lua dofile([[$root/tests/harness.lua]])"
}

for name in core context input targets; do
  run_case "$name"
done

printf '\nAll agent-bridge tests passed.\n'
