# Cross-platform configuration audit

Last audited: 2026-07-28

Source branch: `normalize/multi-platform` (use this file's Git commit as the
audited baseline)

Profiles: native Windows/Git Bash, Ubuntu WSL, macOS, EndeavourOS/Arch

This is the authoritative current-state report for the multi-platform Chezmoi
configuration. It replaces the migration-era divergence inventory. The old
inventory was useful while decisions were unresolved, but it mixed obsolete
snapshots, completed decisions, rollback history, and current policy.

## Executive summary

The configuration is healthy and substantially unified. The four supported
profiles share the same application configuration and differ mainly at real OS
boundaries. At the final audited commit, each machine has a clean source clone
and all four pass:

- `chezmoi status --exclude=dirs`
- `chezmoi verify --exclude=dirs`

The central design is sound:

- Applications use one shared configuration wherever their behavior is
  portable.
- Profile overlays own real platform or machine differences.
- Templates are reserved for differences in paths, launch syntax, or available
  capabilities.
- Credentials, SSH host policy, and machine-specific Git state remain
  unmanaged.
- Arch retains tmux and Workmux as intentional legacy configuration while Herdr
  is the primary workspace manager.

This reassessment found that the setup is not yet down to only unavoidable
specificity:

1. macOS and Arch still contain temporary Volta project and global-CLI
   inventory. Mise now deliberately owns normal Node resolution on every
   profile; when an old Volta project is next used, its version declarations
   must be migrated to a Mise-readable project file. Volta remains callable
   behind Mise's shims for that migration but no longer participates in normal
   Node precedence.
2. Several installations have duplicate or untracked owners: macOS has unused
   `nvm`, `jenv`, and tmux formulae plus a duplicate Homebrew `uv`; Arch has
   unused package-owned Go, `uv`, and `python-pynvim`, while Worktrunk and two
   Python CLIs live in direct Cargo/uv inventories. Superseded Neovim packages
   remain installed on Windows and Arch only until their privileged removals
   are run; they do not win in the supported shells.
3. Native package selections are not recorded declaratively. Mise tools are
   reproducible from this repository, but WinGet, APT, Homebrew, and pacman
   selections currently require this prose audit or live-machine inspection.

These are bounded ownership and transition issues, not evidence that the shared
configuration architecture should be redesigned.

## Supported profiles

The `profile` template identifies four supported environments:

| Profile | Primary shell/workflow | Role |
| --- | --- | --- |
| `windows` | Git Bash and native Windows tools | Native Windows development and Herdr |
| `wsl` | Zsh inside Ubuntu WSL | Linux tooling for Windows-hosted projects |
| `macos` | Zsh | Portable workstation |
| `arch` | Zsh over SSH, Herdr, and retained tmux/Workmux | Remote development host |

Generic `linux` and `unsupported` are defensive fallbacks, not currently
supported configurations. There is no generic-Linux machine to normalize
against today.

## Configuration architecture

### Chezmoi selection

`.chezmoiignore` already implements the desired shared-base model:

1. All four supported profiles receive the shared base by default.
2. Native Windows receives Bash; Unix profiles receive shared Zsh plus one
   overlay.
3. macOS/Arch workstation applications, Arch legacy tools, and WSL/macOS tunnel
   implementations are narrow additions.
4. Generic Linux and unknown systems remain denied by default.

The rendered managed sets confirm the model. Ignoring the newly integrated
Agent Review design notes during the pre-sync snapshot, the only path-level
differences were the expected shell files, one profile overlay, macOS/Arch
LazyDocker and Posting, the WSL/macOS tunnel, and Arch's retained legacy tools.

### Shared base

The shared base currently includes:

- Git defaults and global ignores
- GitHub CLI configuration
- Neovim/LazyVim and Agent Review
- LazyGit and its Neovim target bridge
- Yazi and its Neovim target bridge
- Herdr core configuration and shared plugins
- OpenCode configuration and account-selection helpers
- Pi configuration
- Starship, Atuin, Bat, and portable shell helpers

### Shell ownership

- `~/.config/shell/common.sh` owns portable Bash/Zsh behavior.
- Native Windows owns `.bash_profile` and `.bashrc` for Git Bash.
- WSL, macOS, and Arch share `.zshenv`, `.zshrc`, and the Antidote plugin list.
- `.wsl.zsh`, `.mac.zsh`, and `.arch.zsh` own profile-specific behavior.
- Project helpers for Greenlight and Vimme are shared on Unix and guard their
  checkout paths before doing anything.

### Local and secret state

The following intentionally remain outside ordinary Chezmoi management:

- `~/.ssh/config` and `known_hosts`
- Git credential helpers and machine-only Git settings in
  `~/.config/git/local.config`
- GitHub CLI account records and tokens in `hosts.yml` or native keyrings
- OpenCode authentication files
- Herdr generated registries, caches, logs, and runtime state
- Neovim's `lazy-lock.json`

The RSA SSH key pair has an opt-in 1Password-backed Chezmoi bootstrap path. It
is ignored unless `CHEZMOI_INCLUDE_SECRETS=1`; raw local key storage and direct
machine-to-machine recovery remain acceptable.

### Read-only health check

`dotfiles-doctor` is managed on all four profiles and was verified from native
Windows/Git Bash, WSL, macOS, and Arch. It reports:

- Required executable versions and the exact paths selected by each shell
- Optional runtime and Yazi preview capabilities
- GitHub's preferred transport and the unmanaged local Git overlay
- Chezmoi source state, target status, and verification
- Desired, missing, disabled, and extra Herdr plugins
- Windows compatibility-clone refs/remotes and persistent environment variables

`[FAIL]` results produce a nonzero exit status. `[WARN]` identifies state that
deserves attention but is not necessarily broken, while `[--]` records an
optional capability that is not installed. The command never installs, updates,
applies, or removes anything.

## Managed behavior by platform

| Area | Windows | WSL | macOS | Arch |
| --- | --- | --- | --- | --- |
| Shell | Git Bash | Shared Zsh + WSL overlay | Shared Zsh + Mac overlay | Shared Zsh + Arch overlay |
| Git/gh | Shared core, local GCM | Shared core, local URL-scoped gh helper | Shared core, local Keychain | Shared core, local URL-scoped gh helper |
| Neovim | Shared; native path/launcher guards | Shared | Shared | Shared |
| LazyGit | Shared; commands wrapped through Git Bash | Shared Unix commands | Shared Unix commands | Shared Unix commands |
| Yazi | Shared; native opener and Git Bash Neovim bridge | Shared; `xdg-open` | Shared; `open` | Shared; `xdg-open` |
| Herdr | Shared core; preview channel and Git Bash shell | Shared core | Shared core | Shared core plus legacy popup entry |
| Herdr plugins | Four private compatibility clones linked locally | Four upstream plugins | Four upstream plugins | Four upstream plugins |
| Tunnel | None | systemd user-service implementation | SSH ControlMaster implementation | None |
| LazyDocker/Posting | None | None | Managed | Managed |
| tmux/Workmux | None | tmux installed, config not managed | tmux installed, Workmux removed | Managed as intentional legacy |
| Worktrunk user config | Shared portable config and plugin bridge | Shared portable config and plugin bridge | Shared portable config and plugin bridge | Shared portable config plus Ultralight hooks and seed helper |

### Specificity assessment

The remaining differences fall into three categories. Treating these categories
separately is more useful than calling all of them platform-specific.

**Inherent OS or shell differences — keep:**

- Git Bash versus Zsh startup files
- Windows command strings launched through `cmd.exe` or Git Bash
- `start`, `open`, and `xdg-open` system openers
- Windows Neovim shell, compiler path, Oxfmt launcher, and markdown-preview
  installer handling
- Windows persistent PATH reconciliation and ble.sh bootstrap
- WSL systemd tunnel services versus macOS SSH ControlMaster sockets
- WSL's Windows-process bridge for the native PoE2 application

These are narrow and live at appropriate boundaries: Chezmoi selection,
application launcher templates, or small bootstrap scripts.

**Temporary compatibility differences — remove when their blockers end:**

- Windows Herdr preview builds and four private plugin compatibility branches
- the Windows-only Mise `pipx:pynvim` shim-reentry workaround
- Volta on macOS and Arch during project-by-project Node migration
- miscellaneous direct-release user CLI installs on WSL

The Windows Herdr and pynvim cases are already isolated and documented well.
The Volta transition is intentionally one-way: Mise owns normal resolution,
while Volta remains available only to inspect and migrate legacy state.

**Host-role policy expressed through an OS profile — acceptable today, but not
intrinsically OS-specific:**

- Arch's retained tmux/Workmux stack
- Arch's Ultralight Worktrunk seeding and cleanup hooks
- macOS/Arch LazyDocker and Posting management
- macOS workstation aliases and Arch Tailscale service aliases

There is one machine per profile, so adding a second dimension would currently
add ceremony without changing behavior. If a second Mac or Arch host is added,
split profile data into OS plus capabilities/role (for example `workstation`,
`remote_host`, `legacy_tmux`, and `ultralight_host`) instead of copying more OS
conditions.

### Conditionals removed during this cleanup

- Git configuration is now a plain shared source file.
- Herdr's desired plugin inventory no longer repeats identical profile arrays.
- `.chezmoiignore` now describes a shared base with narrow exclusions.
- Portable aliases formerly repeated in Unix overlays now live in shared shell
  layers with capability or profile guards.

## Tool installation and provenance

### Installation heuristic

Use one owner per executable and choose it in this order:

1. **OS package manager** for system libraries, desktop applications, shells,
   and standalone CLIs when its version satisfies the configuration.
2. **Mise** for programming-language runtimes, project-selected tool versions,
   runtime-distributed developer CLIs, and the WSL fallback when APT is missing
   or materially behind a required CLI.
3. **Official application installer/release** only when the application needs a
   preview channel, is absent from the first two layers, or intentionally owns
   its own update lifecycle.
4. **Direct ecosystem-global installs** (`npm -g`, `uv tool`, `cargo install`)
   only when no better owner exists. Prefer Mise's `npm:`, `pipx:`, `cargo:`, or
   `aqua:` backend so the tool remains in one declared inventory.

This follows [Mise's documented scope](https://mise.jdx.dev/faq.html#mise-is-for-dev-tools-not-applications-or-system-packages):
development tools and CLI utilities, not system libraries or desktop
applications. Native package selections should be recorded without making
Chezmoi silently install or remove them: a
[WinGet configuration](https://learn.microsoft.com/en-us/windows/package-manager/winget/configure),
an [APT package list](https://ubuntu.com/server/docs/how-to/software/package-management/),
a [Brewfile](https://docs.brew.sh/Brew-Bundle-and-Brewfile), and an Arch
explicit-package list are the appropriate next layer. These native tools are
designed to restore or test declared package state.

### Current owner and recommendation

`current → recommended` is shown only where this audit recommends a change.

| Tool/group | Windows | WSL | macOS | Arch |
| --- | --- | --- | --- | --- |
| Git / Git LFS / gh | WinGet / bundled | APT | Apple Git + Homebrew | pacman |
| Chezmoi | WinGet | Mise | Homebrew | pacman |
| Neovim | Mise `neovim@nightly`; superseded WinGet stable pending elevated removal | Mise `neovim@nightly` | Mise `neovim@nightly` | Mise `neovim@nightly`; superseded pacman nightly pending `sudo` removal |
| LazyGit | WinGet | Mise | Homebrew | pacman |
| Herdr | official preview installer | official release | official release | official release |
| OpenCode | official installer | official installer | official installer | official installer |
| Mise itself | WinGet | official installer | Homebrew | pacman |
| Node development runtime | Mise | Mise | Mise; Volta retained only for incremental migration | Mise; Volta retained only for incremental migration |
| Python development runtime | Mise | Mise | Mise; Homebrew dependency retained | Mise; pacman system Python retained |
| Go development runtime | Mise | Mise | Mise | Mise; remove unused explicit pacman Go |
| Java / Maven | not currently needed | not currently needed | Mise Temurin 17/11 + Maven | Mise Temurin 17/11 + Maven |
| Bun | not required by Windows plugin forks | official installer → Mise | official installer → Mise | official installer → Mise |
| Pi / Neovim Node host | Mise `npm:` | Mise `npm:` | Mise `npm:` | Mise `npm:` |
| uv / Neovim Python host | Mise | Mise | Mise; remove Homebrew leaf `uv` | Mise; remove explicit pacman `uv` and `python-pynvim` |
| Tree-sitter CLI | Mise | Mise | Homebrew | pacman |
| Worktrunk | WinGet | direct Cargo → Mise `aqua:max-sixty/worktrunk` | Homebrew | direct Cargo → Mise `aqua:max-sixty/worktrunk` until pacman is version-compatible |
| Starship / Atuin / Yazi | WinGet | direct releases → Mise `aqua:` | Homebrew | pacman |
| Bat / fzf / fd / ripgrep | WinGet | APT | Homebrew | pacman |
| jq / zoxide | WinGet | direct releases → Mise `aqua:` or APT if its version suffices | Homebrew | pacman |
| LLVM / compilers | WinGet LLVM | APT only as needed | Homebrew/Xcode only as needed | pacman only as needed |
| 1Password CLI | WinGet | official APT repository | Homebrew | pacman |
| LazyDocker | not needed | not needed | Homebrew | pacman |
| Posting | not needed | not needed | Homebrew | direct `uv tool` → Mise `pipx:posting` |
| LazyJira | not needed | not needed | trusted Homebrew formula | not needed |
| tmux / Workmux | not needed | tmux package, unmanaged | unused Homebrew tmux → remove | pacman tmux + retained local Workmux |

### Live version snapshot

These are the executables actually resolved during the reassessment, not merely
the versions recorded by package databases.

| Tool | Windows | WSL | macOS | Arch |
| --- | --- | --- | --- | --- |
| Git | 2.55.0 | 2.53.0 | Apple Git 2.50.1 | 2.55.0 |
| Neovim | 0.13.0-dev-1141+ge3c5974adf | 0.13.0-dev-1141+ge3c5974adf | 0.13.0-dev-1141+ge3c5974adf | 0.13.0-dev-1141+ge3c5974adf |
| Herdr | 0.7.5 preview | 0.7.5 | 0.7.5 | 0.7.5 |
| OpenCode | 1.18.7 | 1.18.7 | 1.18.7 | 1.18.7 |
| Pi | 0.82.1 | 0.82.1 | 0.82.1 | 0.82.1 |
| Mise | 2026.7.15 | 2026.7.11 | 2026.7.15 | 2026.7.10 |
| Interactive Node | 24.18.0 Mise | 24.18.0 Mise | 24.18.0 Mise | 24.18.0 Mise |
| Interactive Python | 3.14.6 Mise | 3.14.6 Mise | 3.14.6 Mise | 3.14.6 Mise |
| Go | 1.26.5 Mise | 1.26.5 Mise | 1.26.5 Mise | 1.26.5 Mise |
| uv / pynvim provider | 0.11.32 / 0.6.0 | 0.11.32 / 0.6.0 | 0.11.32 / 0.6.0 | 0.11.32 / 0.6.0 |
| Worktrunk | 0.69.2 | 0.69.2 | 0.69.2 | 0.69.2 |

| Small tool | Windows | WSL | macOS | Arch |
| --- | --- | --- | --- | --- |
| Starship | 1.26.0 | 1.26.0 | 1.26.0 | 1.26.0 |
| Atuin | 18.18.0 | 18.18.1 | 18.17.1 | 18.17.1 |
| Bat | 0.26.1 | 0.26.1 | 0.26.1 | 0.26.1 |
| Yazi | 26.5.6 | 26.5.6 | 26.5.6 | 26.5.6 |
| jq | 1.8.2 | 1.8.2 | 1.8.2 | 1.8.2 |
| zoxide | 0.10.0 | 0.10.0 | 0.10.0 | 0.10.0 |
| fzf | 0.74.1 | 0.67.0 | 0.74.0 | 0.74.1 |
| fd | 10.4.2 | 10.3.0 | 10.4.2 | 10.4.2 |
| ripgrep | 15.2.0 | 15.1.0 | 15.2.0 | 15.2.0 |

The minor Atuin/fzf/fd/ripgrep differences are normal native-repository lag and
do not affect the shared configuration. At audit time WinGet offered Atuin
18.18.1; Homebrew and Arch also had routine upgrades pending. Package currency
is maintenance state, not a reason to move every healthy native package to
Mise.

### Notable version and manager drift

- Python 3.14.6 is owned by Mise for interactive development on all four
  profiles, and `.python-version` is enabled as a common project declaration.
  Windows PowerShell, Git Bash, and WSL-to-Windows interop resolve `python`,
  `python3`, `pip`, and `pip3` through the same Mise runtime. Interactive Zsh
  resolves Mise Python on WSL, macOS, and Arch. A noninteractive macOS command
  may resolve Homebrew Python first; that is acceptable for package-owned tools
  and should not be described as the development-runtime path.
- Windows's standalone Python 3.12, legacy launcher, Python Install Manager, and
  manager-owned 3.14 runtime were removed after the Mise runtime passed the
  native application's full suite both before and after cleanup. The Windows
  `py`/`pymanager` commands are intentionally absent. A Windows-only
  reconciliation script keeps Mise's shims first in the persistent user `PATH`
  without deleting or reordering any other entry, and backs up the previous
  value before changing it.
- Homebrew and pacman Python installations remain installed for package-owned
  utilities even though Mise wins in development shells. Arch's explicit
  `python-pynvim` package is redundant because Neovim already selects the
  isolated Mise provider.
- Mise discovery ceilings now live in its shell-independent early-init
  `miserc.toml`. Every profile stops at its home; WSL also stops at the mounted
  Windows home, preventing native Windows global configuration from leaking
  into WSL projects.
- Mise configuration is shared and profile-aware without changing unrelated
  tool ownership: Windows and WSL retain their prior tools, while macOS and Arch
  now use Mise for Temurin Java 17/11 and Maven 3.9.16. Plain Java version
  declarations align with existing `.java-version` files, and
  `java.shorthand_vendor = "temurin"` keeps the selected distribution explicit.
- Go 1.26.5 is selected from Mise on all four profiles. GOPATH is left unset so
  Go uses its standard home-directory default, and `go.set_gobin = false` keeps
  installed commands in the canonical `~/go/bin`. Arch also has an explicit,
  unused pacman Go installation with no reverse dependencies; that is duplicate
  ownership and should be removed.
- Jabba is retired on macOS and Arch. Its shell integration and managed source
  are gone; the old JDK trees were moved to each platform's Trash for recovery.
- macOS now uses Homebrew for Bat, `fd`, and ripgrep; their obsolete Cargo
  copies have been removed.
- Earlier macOS package drift is resolved, but the live reassessment found four
  remaining explicit Homebrew leaves that do not match current policy: `nvm`,
  `jenv`, tmux, and duplicate `uv`. LazyJira remains intentionally installed
  and only its specific third-party formula is trusted.
- Bun 1.3.14 is installed through the official installer on WSL, macOS, and
  Arch because the upstream Herdr title plugin uses it. Bun is a runtime and is
  available through Mise; moving these three installs into Mise would match the
  runtime policy and remove another self-managed tree.
- Native Windows and WSL use Mise for Node. Windows has no checked-out projects
  with Volta, `.nvmrc`, `.node-version`, or `.tool-versions` Node pins, so its
  standalone Node installation and duplicate npm-global tools have been
  removed. PowerShell and Git Bash both resolve the Mise shims. Mise also owns
  the Neovim Node host and Tree-sitter CLI there instead of Node-global npm
  state.
- Windows retains its WinGet LLVM toolchain. Mise's current `clang` and
  `conda:clang` backends install the correct Conda package but expose a copied
  executable without its runtime DLL directory, causing `0xC0000135`; adding
  another PATH workaround would not improve the configuration. Neovim keeps
  the WinGet LLVM path available for parser builds launched outside Git Bash.
- Neovim is an intentional freshness exception to the native-package-first
  heuristic. Mise declares `neovim@nightly` once for all four profiles and the
  shared `nvu` helper force-refreshes that mutable channel. The former WSL and
  Arch AppImages were moved to each machine's Trash, and the former macOS
  Homebrew formula was removed. Windows still has a superseded WinGet stable
  package because MSI removal requires an elevated terminal; Arch still has a
  superseded `neovim-nightly` package because pacman removal requires `sudo`.
  Neither package wins in the supported Git Bash/Zsh profiles. Ordinary native
  PowerShell will continue to find the Windows stable executable first until
  its elevated removal is completed.
- macOS and Arch retain Volta because checked-out projects contain exact
  `package.json.volta` Node, npm, and Yarn pins and Arch still has Volta-owned
  global CLIs. Mise does not interpret the Volta field directly. Rather than
  maintaining two automatic precedence systems, Mise now owns normal Node
  resolution everywhere. Volta's bin directory remains behind Mise's shims so
  the `volta` command is available for inspection and migration, but its Node
  shims do not override Mise. When an old project is next used, move its pins to
  `.nvmrc`, `.node-version`, `package.json.devEngines`, or a local `mise.toml`.
- [Mise's standard Node version-file support](https://mise.jdx.dev/lang/node.html#automatic-node-version-detection)
  is enabled on every profile, so
  `.nvmrc`, `.node-version`, `.tool-versions`, and `package.json.devEngines`
  can become the common project mechanism. Corepack is enabled for
  Mise-installed Node versions on every profile. macOS and Arch can therefore
  migrate projects incrementally while the `volta` command remains available
  behind Mise. Volta should not be removed until those projects and its global
  CLI inventory have been reconciled.
- Pi is owned by Mise on all four profiles and is no longer part of the Volta
  inventory. Arch still has project-facing Volta global CLIs; those must be
  classified and migrated before Volta removal. The `piu` Volta fallback is now
  dead compatibility code and can be simplified to Mise only.
- The Neovim Node host is Mise-owned on all four profiles. Neovim locates the
  isolated Mise `npm:neovim` package explicitly, while the provider process uses
  the same normal Mise Node resolution as the rest of the environment. The
  former Unix-only `mise which node` PATH injection is no longer necessary.
- The Neovim Python host is an isolated Mise `pipx:pynvim` tool on all four
  profiles. Neovim selects its `pynvim-python` executable directly rather than
  depending on mutable packages inside a development Python runtime. Mise also
  owns the shared `uv` installer used by its `pipx` backend. WSL, macOS, and
  Arch use the normal `mise install` path. A small Windows-only Chezmoi
  bootstrap installs `uv` first, then runs the `pipx:pynvim` install through
  `mise exec uv` to avoid the Windows `uv.exe` shim re-entering Mise. The
  resulting provider remains fully owned by Mise.
- Homebrew `uv` on macOS and pacman `uv` on Arch are explicit duplicates. No uv
  tools are installed on Windows, WSL, or macOS. Arch has direct uv-owned
  `posting` and `harlequin`; migrate those to Mise `pipx:` declarations before
  removing Arch's package-owned uv.
- The unused Hermes installation, its private runtime, and its command shims
  have been removed from Arch.
- Worktrunk is aligned at 0.69.2 on all four profiles, but WSL and Arch use
  direct Cargo inventories. [Worktrunk documents native WinGet, Homebrew,
  pacman, and Cargo installs](https://github.com/max-sixty/worktrunk#install),
  while Mise's registry exposes the official Worktrunk
  release through `aqua:max-sixty/worktrunk`; using that on WSL and Arch would
  remove two unmanaged installs and eliminate Rust as installation machinery
  where no checked-out Rust project exists.
- WSL's direct-release Starship, Atuin, Yazi, jq, and zoxide binaries are
  individually current but have no shared declaration or owner. APT is
  materially behind or missing several of them. Mise's registry exposes these
  tools through vetted release backends, so one WSL-specific Mise block is a
  simpler fallback tier than five bespoke release installations.
- Windows ble.sh remains a release-tree installation under
  `~/.local/share/blesh`; a Windows-only Chezmoi bootstrap installs the upstream
  nightly build when that tree is missing and never replaces an existing copy.
  Updates are intentionally explicit through ble.sh's built-in `ble-update`;
  automatic nightly replacement could destabilize shell bindings.
- Atuin remains installed on macOS for local shell history, but its unused and
  failing background daemon service has been removed. Automatic sync remains
  disabled in the shared configuration.
- Further Mise adoption remains selective. Native package managers still own
  system libraries, desktop applications, and healthy standalone packages;
  Mise owns runtimes and fills user-CLI gaps where the native repository is
  absent or materially stale.

## Application findings

### Git and GitHub

- New GitHub operations prefer SSH on all four platforms.
- Machine-local credential helpers remain necessary for legacy HTTPS remotes.
- The same RSA key is used across the four setups and is registered with GitHub.
- Credentials, account records, SSH config, and known-host policy are correctly
  excluded from the repository.
- Git configuration is a plain shared Chezmoi source file.

### Pi

- `openai-codex-personal` is the canonical shared default provider.
- `/profile work --project` stores the normal work override in a repository's
  local `.pi/settings.json`; `/profile work` remains available for an ad hoc
  global switch.
- An ad hoc global switch updates the managed user settings file, so it may
  appear as temporary Chezmoi drift. Do not promote that transient work choice
  into the shared source; the next explicit apply restores the personal default.

### Neovim

- The shared LazyVim tree works on all four profiles.
- Mise owns the same official nightly build on all four profiles. `nvu`
  refreshes the mutable nightly tag with `mise install --force
  neovim@nightly`; it was exercised successfully on WSL after migration.
- TypeScript, Python, and Go support are enabled on all four profiles. Native
  Windows now has the complete LazyVim Go toolset, including gopls.
- LazyGit, Yazi, and Agent Review can target an existing Neovim instance.
- `lazy-lock.json` is intentionally unmanaged runtime state.
- Retired Neoconf/Neodev configuration and the contradictory Refactoring extra
  declaration are gone; the intentional `refactoring.nvim` disable remains.

### LazyGit and Yazi

The two applications now share the same architectural idea:

1. Find the appropriate Neovim target through the shared target registry.
2. Open or edit through a small application-specific bridge.
3. Close or return from a Herdr popup without teaching the application about
   the workspace manager.

The application-specific helpers should remain separate because their protocols
and exit behavior differ. The target-discovery library is the correct shared
boundary.

Yazi's core behavior works on all four profiles. Optional preview coverage is
uneven:

| Preview dependency | Windows | WSL | macOS | Arch |
| --- | --- | --- | --- | --- |
| FFmpeg | Yes | No | Yes | Yes |
| PDF renderer (`pdftoppm`) | No | No | No | Yes |
| ImageMagick | No | No | Yes | Yes |
| `chafa` | No | No | No | No |
| Archive helper | No | No | Yes (`bsdtar`) | Yes |

These are optional enhancements, not blockers. Ordinary terminal copy/paste and
Yazi file yank/paste already work without adding Wayland/X11 clipboard tools.

The empty Yazi keymap and two unselected theme variants have been removed.

### Herdr and plugins

Shared behavior now includes directional pane movement, pane resizing,
full-height layouts, Worktrunk access, popup picking, and LazyGit/Yazi bridges.
Windows uses private compatibility forks for the four desired plugins; Unix
profiles use upstream repositories.

The desired inventory contains:

- `edi.layout-tools`
- `herdr-splits`
- `worktrunk`
- `rjyo.window-title-sync`

The first Chezmoi apply each month updates Unix plugins from their upstream
default refs and fast-forwards Windows compatibility clones from their private
branches. Windows public upstreams are fetched but never auto-merged. The
doctor validates desired/enabled state plus Windows branch, origin, upstream,
and cleanliness. Undeclared plugins are reported but require explicit removal.

### Shell and small tools

- Atuin works across Bash and Zsh, including the corrected Git Bash Ctrl-R
  binding through ble.sh.
- Git Bash exposes native Herdr, LLVM, Starship, GitHub CLI, and OpenCode paths
  before its interactive-shell guard, so automation and interactive terminals
  resolve the same required tools.
- The checked-in Atuin file now contains only the intentional local-history,
  session-up-arrow, style, Enter-accept, and record-sync settings.
- Bat uses its bundled Catppuccin Mocha theme on all four profiles; redundant
  checked-in Bat themes and two unused Yazi theme variants were removed.
- `nvu` is a portable shared Mise updater for `neovim@nightly` and reports the
  resulting Neovim version after a successful refresh.
- `ha` and `hat` have one WSL/macOS definition in the templated Zsh layer.
- The unused `gou` curl-to-shell installer alias has been removed. Mise now owns
  Go upgrades on all four profiles.
- `piu` still contains a Volta fallback even though Pi is Mise-owned everywhere;
  `uvu` manages an empty uv tool inventory on three machines; and `rcu` exists
  primarily for the direct Cargo installs targeted above. Revisit all three
  after the ownership migrations rather than preserving obsolete update paths.
- Greenlight's duplicate `frontend/settings` pull has been removed.
- Greenlight repositories use machine-local path-scoped Git identity includes;
  `gggm` no longer mutates global identity while running `good morning`.

## Reassessment action list

This order separates correctness from optional ownership cleanup. Every change
should still be previewed narrowly and verified on the affected machines.

1. **Volta migration — incremental.** Mise now owns normal Node resolution on
   every profile. As macOS/Arch Volta projects are next used, translate their
   runtime pins into Mise-readable declarations. Do not remove Volta until
   Arch's global package inventory has also been classified and migrated.
2. **Neovim ownership — functionally complete; privileged cleanup remains.**
   Mise nightly and both providers pass on all four profiles. Remove the
   superseded Windows stable package from an Administrator terminal with
   `winget uninstall --id Neovim.Neovim --exact`, and remove Arch's superseded
   package with `sudo pacman -R neovim-nightly`. Do not use `pacman -Rs`: its
   removal plan includes shared libraries that may remain useful. Then consider
   removing Arch `python-pynvim`, which the Mise provider has replaced.
3. **Duplicate runtimes — straightforward after checks.** Remove macOS
   Homebrew `uv`; remove Arch pacman `uv` and Go after migrating Arch's uv tools
   to Mise. Keep system Python and dependency-owned Node on Arch.
4. **Runtime-distributed CLIs — low risk.** Declare Arch Posting and Harlequin
   through Mise `pipx:`. Move WSL/Arch Worktrunk to
   `aqua:max-sixty/worktrunk`. Then reassess whether WSL Mise Rust, Arch system
   Rust, `cargo-update`, `rcu`, and `uvu` still have a purpose.
5. **Bun ownership — low risk.** Move WSL, macOS, and Arch from the official
   Bun tree to Mise, verify the title-sync plugin, then remove `.bun` PATH and
   completion setup if no other consumer remains.
6. **macOS dead leaves — confirm, then remove.** `nvm`, `jenv`, and tmux are
   explicit Homebrew leaves with no managed integration. Their removal matches
   current policy unless there is an unmanaged use not visible to this audit.
7. **WSL CLI consolidation — optional but recommended.** Move direct-release
   Starship, Atuin, Yazi, jq, and zoxide into the WSL Mise block. Leave healthy
   APT-owned Bat, fzf, fd, and ripgrep alone.
8. **Package manifests — recommended architectural follow-up.** Add a narrow
   WinGet configuration, WSL APT list, macOS Brewfile, and Arch explicit-package
   list. They should support check/plan and explicit bootstrap, not automatic
   removal during ordinary `chezmoi apply`.
9. **Optional previews remain optional.** Do not add media, PDF, image, archive,
   `chafa`, or `resvg` dependencies merely for parity.

The Arch tmux and Workmux sources remain intentional legacy configuration.
Arch's Ultralight hooks and macOS/Arch workstation applications are host-role
policy, not cleanup debt. Jabba, Hermes, `.profile`, stale Neovim configuration,
and the old duplicated themes/helpers remain correctly retired.

## Verification policy

For every cross-machine change:

1. Inspect the rendered diff before applying.
2. Apply only explicit paths rather than the entire source state.
3. Preserve a timestamped backup for non-trivial live configuration changes.
4. Run `chezmoi verify --exclude=dirs` immediately afterward.
5. Confirm `chezmoi status --exclude=dirs` and the affected interactive behavior.
6. Commit and push the source branch before updating the other native clones.

This report should be refreshed after each cleanup milestone so it remains a
description of the current system, not a second historical backlog.
