# Herdr integration and plugin management

Chezmoi manages the desired agent integrations and shared plugin inventory,
shared keybindings, and user-owned plugin configuration. Herdr continues to own
its generated integration files, `plugins.json` registry, managed GitHub
checkouts, caches, logs, and state.

The source-only files are:

- `.chezmoidata/herdr.yaml` — the desired integrations, four desired plugins,
  and Windows compatibility-clone metadata
- `.chezmoiscripts/run_onchange_after_30-herdr.sh.tmpl` — install or update
  desired integrations and plugins on Arch, macOS, and WSL
- `.chezmoiscripts/run_onchange_after_30-herdr.ps1.tmpl` — install or update
  desired integrations, then clone, update, validate, and link the private
  Windows-compatible plugin repositories

The rendered scripts include the current date. Consequently, the first
`chezmoi apply` each day refreshes integrations and plugins automatically, and
the scripts also run immediately whenever their inventory or implementation
changes. Once they run, `chezmoi status` returns to clean instead of permanently
showing an always-run script.

## Agent integrations

Every profile installs the Herdr integrations for Pi, Claude, Codex, OpenCode,
and Cursor. Installation is idempotent and updates an older generated hook or
extension in place. `dotfiles-doctor` requires every declared integration to be
installed and current, while ignoring undeclared integrations.

Herdr owns the generated integration files because their formats and versions
follow the installed Herdr release. Removing an integration remains an explicit
`herdr integration uninstall <name>` operation followed by removing it from the
inventory.

## Plugin update and removal policy

On WSL, macOS, and Arch, reconciliation reruns `herdr plugin install` for every
desired upstream source. That resolves the current upstream default ref and
replaces an older managed checkout. A failed update preserves an already
installed copy, but failure to install a missing required plugin stops the
apply.

On Windows, reconciliation automatically clones a missing private repository,
requires the documented clean branch, validates its `origin` and `upstream`,
fast-forwards from the private `origin` branch, fetches public `upstream`, and
relinks the clone. Public upstream is deliberately never auto-merged into a
compatibility branch: those merges may conflict with Windows-specific changes
and need review before they are pushed to the private branch.

Reconciliation is additive. Every declared plugin must be present and enabled,
but an undeclared plugin is only reported by `dotfiles-doctor`; it is not
silently uninstalled. This allows temporary plugin evaluation without an apply
deleting it. Removing an unwanted plugin remains an explicit
`herdr plugin uninstall` operation.

## Windows compatibility clones

Windows links private clones under `~/dev`. They are not submitted to the Herdr
registry and are not intended as supported public packages.

| Plugin | Private repository | Development ref | Local path |
| --- | --- | --- | --- |
| Layout Tools | `jeffhertzler/herdr-layout-tools-windows` | `agent/windows-support` | `~/dev/herdr-layout-tools-windows` |
| Herdr Splits | `jeffhertzler/herdr-splits-windows` | `agent/windows-support` | `~/dev/herdr-splits-windows` |
| Worktrunk | `jeffhertzler/herdr-worktrunk-windows` | `agent/windows-support` | `~/dev/herdr-worktrunk-windows` |
| Window Title Sync | `jeffhertzler/herdr-window-title-sync-windows` | `agent/windows-support` | `~/dev/herdr-window-title-sync-windows` |

Window Title Sync uses Bun on every profile. The Windows compatibility branch
stays aligned with upstream's runtime and only adds portable temporary/home
directory handling plus session-file discovery through Bun's filesystem API
instead of Unix `find`.
