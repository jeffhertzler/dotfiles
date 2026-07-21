#!/usr/bin/env bash
set -euo pipefail

command -v herdr >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || {
  printf 'herdr plugin bootstrap: jq is required; skipping\n' >&2
  exit 0
}

plugins=(
  'herdr-splits=lmilojevicc/herdr-splits.nvim'
  'edi.layout-tools=edouard-andrei/herdr-layout-tools'
  'worktrunk=devashish2203/herdr-worktrunk'
  'rjyo.window-title-sync=rjyo/herdr-window-title-sync'
)

mapfile -t sessions < <(
  herdr session list --json 2>/dev/null |
    jq -r '.sessions[]?.name' |
    awk 'NF && !seen[$0]++'
)
((${#sessions[@]} > 0)) || sessions=(default)

for session in "${sessions[@]}"; do
  installed=$(herdr --session "$session" plugin list --json 2>/dev/null |
    jq -r '.result.plugins[]?.plugin_id')

  for plugin in "${plugins[@]}"; do
    id=${plugin%%=*}
    source=${plugin#*=}
    if grep -Fxq "$id" <<<"$installed"; then
      continue
    fi

    printf 'Installing Herdr plugin %s in session %s\n' "$source" "$session"
    herdr --session "$session" plugin install "$source" --yes
  done
done
