#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tests_root="$plugin_root/tests"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/agent-review-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

run_case() {
  local name=$1
  local state=$2
  local file=$3
  local timeout_seconds=${4:-20}
  shift 4 || true

  AGENT_REVIEW_PLUGIN_ROOT="$plugin_root" \
  AGENT_REVIEW_TEST_CASE="$tests_root/cases/$name.lua" \
  AGENT_REVIEW_TEST_FILE="$file" \
  AGENT_REVIEW_TEST_TMP="$tmp/$name-work" \
  NVIM_AGENT_REVIEW_STATE="$state" \
    timeout "${timeout_seconds}s" nvim --headless -i NONE -u "$tests_root/minimal_init.lua" \
      "+lua dofile([[${tests_root}/harness.lua]])"
}

make_file() {
  local path=$1
  printf 'header\nlocal value = 200\ntarget line\nchange me\nfooter\n' >"$path"
}

for name in core columns input commands rpc rpc_unopened bridge codediff_mapping agent_diff agent_diff_changeset; do
  file="$tmp/$name.lua"
  state="$tmp/$name.json"
  make_file "$file"
  run_case "$name" "$state" "$file" 20
 done

file="$tmp/persistence.lua"
state="$tmp/persistence.json"
make_file "$file"
run_case persistence_seed "$state" "$file" 20
run_case persistence_verify "$state" "$file" 20

file="$tmp/migration.lua"
state="$tmp/migration.json"
make_file "$file"
cat >"$state" <<JSON
{"schemaVersion":1,"annotations":[{"id":"review-7","author":{"kind":"human","name":"test"},"body":"migrate me","kind":"note","status":"open","freshness":"fresh","revision":{"backend":"files","selectedExpression":"WORKING"},"target":{"file":"$file","side":"working","startLine":1,"endLine":1,"selection":"line","columnEncoding":"utf-8-byte"},"anchor":{"before":[],"selected":["header"],"after":["local value = 200"]}}]}
JSON
run_case migration "$state" "$file" 20

file="$tmp/reanchor.lua"
state="$tmp/reanchor.json"
printf 'alpha\nmove me\nomega\nchange me\nend\n' >"$file"
run_case reanchor_seed "$state" "$file" 20
printf 'intro\nalpha\nmove me\nomega\nchanged\nend\n' >"$file"
run_case reanchor_verify "$state" "$file" 20

file="$tmp/sessions.lua"
state="$tmp/sessions.json"
make_file "$file"
run_case sessions_seed "$state" "$file" 20
run_case sessions_verify "$state" "$file" 20

file="$tmp/codediff-placeholder.lua"
state="$tmp/codediff.json"
make_file "$file"
run_case codediff "$state" "$file" 30

printf '\nAll agent-review tests passed.\n'
