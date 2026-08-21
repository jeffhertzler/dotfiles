# Herdr integration and plugin management

Chezmoi manages the desired agent integrations and shared plugin inventory,
shared keybindings, and user-owned plugin configuration. Herdr continues to own
its generated integration files, `plugins.json` registry, managed GitHub
checkouts, caches, logs, and state.

The source-only files are:

- `.chezmoidata/herdr.yaml` — the desired integrations, four desired plugins,
  maintained-fork metadata, and Windows compatibility metadata
- `dot_local/bin/executable_herdr-plugin-reconcile.mjs` — clone, validate,
  fast-forward, fetch upstream, and link a user-maintained plugin checkout
- `.chezmoiscripts/run_onchange_after_30-herdr.sh.tmpl` — install public plugins
  and reconcile maintained plugins on Arch, macOS, and WSL
- `.chezmoiscripts/run_onchange_after_30-herdr.ps1.tmpl` — install integrations
  and reconcile the profile-specific private plugin branches on Windows

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

On WSL, macOS, and Arch, reconciliation reruns `herdr plugin install` for each
public plugin. That resolves the current upstream default ref and replaces an
older managed checkout. A failed update preserves an already installed copy,
but failure to install a missing required plugin stops the apply.

A user-maintained plugin uses the same local-clone reconciler on every profile.
The reconciler requires a clean checkout on the declared branch, validates the
private `origin` and public `upstream`, fast-forwards only from the matching
`origin` branch, fetches public upstream for comparison, and links the checkout
into Herdr. It never merges upstream or pushes either remote.

Worktrunk is the first maintained plugin. Linux, macOS, and WSL link `main` from
`jeffhertzler/herdr-worktrunk`; Windows links `agent/windows-support` from the
same repository. Public `devashish2203/herdr-worktrunk` is `upstream` on both.
Reviewed upstream changes land on maintained `main` before a separate reviewed
merge carries them into the Windows branch.

The Worktrunk fork reports a checkout's PR as the `$pr` workspace token. Herdr's
second space row keeps `$session`, branch, and Git status, then adds that token.
Opening a native worktree workspace starts a nonblocking refresh. Run
`herdr plugin action invoke refresh-pr --plugin worktrunk` to refresh the focused
workspace after a PR changes state. A branch with no PR clears an old value;
missing GitHub CLI authentication and network failures do not stop checkout
opening.

There is no separate open-PR action. Worktrunk's native picker opens the selected
PR with `Alt+O`.

Reconciliation is additive. Every declared plugin must be present and enabled,
but an undeclared plugin is only reported by `dotfiles-doctor`; it is not
silently uninstalled. This allows temporary plugin evaluation without an apply
deleting it. Removing an unwanted plugin remains an explicit
`herdr plugin uninstall` operation.

## Worktrunk picker

`prefix+shift+g` invokes `worktrunk.open`, which runs Worktrunk's native switch
picker with linked worktrees, local branches, remote branches, and open pull or
merge requests. Worktrunk owns its previews and `Enter`, `Alt-C`, `Alt-X`, and
`Escape` behavior. The maintained plugin passes a successful switch result to
Herdr's worktree workspace command and closes Herdr workspaces whose checkouts
`Alt-X` removed.

The managed plugin config uses an `85%` by `75%` popup. Change
`picker_placement` to `"overlay"` in
`dot_config/herdr/plugins/config/worktrunk/config.toml` for a full-terminal
picker; overlay placement ignores the popup dimensions. The separate
`worktrunk.new-current` action uses a compact popup for creating a checkout from
the current branch.

`prefix+ctrl+x` invokes `worktrunk.remove-current`. It pins the focused linked
checkout before showing its confirmation, keeps Worktrunk's safety checks and
hooks, and closes the matching Herdr workspace only after successful removal.
Removing another checkout remains available through `Alt+X` in the native
picker.

## Private plugin clones

Private clones live under `~/dev`. They are not submitted to the Herdr registry
and are not intended as supported public packages.

| Plugin | Private repository | Ref | Profiles | Local path |
| --- | --- | --- | --- | --- |
| Layout Tools | `jeffhertzler/herdr-layout-tools-windows` | `agent/windows-support` | Windows | `~/dev/herdr-layout-tools-windows` |
| Herdr Splits | `jeffhertzler/herdr-splits-windows` | `agent/windows-support` | Windows | `~/dev/herdr-splits-windows` |
| Worktrunk | `jeffhertzler/herdr-worktrunk` | `main` | Linux, macOS, WSL | `~/dev/herdr-worktrunk` |
| Worktrunk | `jeffhertzler/herdr-worktrunk` | `agent/windows-support` | Windows | `~/dev/herdr-worktrunk` |
| Window Title Sync | `jeffhertzler/herdr-window-title-sync-windows` | `agent/windows-support` | Windows | `~/dev/herdr-window-title-sync-windows` |

Window Title Sync uses Bun on every profile. The Windows compatibility branch
stays aligned with upstream's runtime and only adds portable temporary/home
directory handling plus session-file discovery through Bun's filesystem API
instead of Unix `find`.
