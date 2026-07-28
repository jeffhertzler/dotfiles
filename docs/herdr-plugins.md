# Herdr plugin management

Chezmoi manages the desired shared plugin inventory, shared keybindings, and
user-owned plugin configuration. Herdr continues to own its generated
`plugins.json` registry, managed GitHub checkouts, caches, logs, and state.

The source-only files are:

- `.chezmoidata/herdr-plugins.yaml` — desired plugins and Windows link metadata
- `.chezmoiscripts/run_onchange_after_30-herdr-plugins.sh.tmpl` — install or
  enable missing desired plugins on Arch, macOS, and WSL
- `.chezmoiscripts/run_onchange_after_30-herdr-plugins.ps1.tmpl` — link or
  enable the private Windows-compatible clones

The reconcilers are additive: they never uninstall plugins that are absent
from the inventory.

## Windows compatibility clones

Windows links local clones under `~/dev` so compatibility changes can be tested
before they are folded into a stable branch. Each clone has a private `origin`
and the public project as `upstream`:

| Plugin | Private repository | Development ref | Local path |
| --- | --- | --- | --- |
| Layout Tools | `jeffhertzler/herdr-layout-tools-windows` | `agent/windows-support` | `~/dev/herdr-layout-tools-windows` |
| Herdr Splits | `jeffhertzler/herdr-splits-windows` | `agent/windows-support` | `~/dev/herdr-splits-windows` |
| Worktrunk | `jeffhertzler/herdr-worktrunk-windows` | `agent/windows-support` | `~/dev/herdr-worktrunk-windows` |

On a new Windows machine, clone those private repositories at the listed refs
before applying Chezmoi. The PowerShell reconciler deliberately fails with the
missing clone and expected ref rather than silently cloning or replacing a
development checkout.
