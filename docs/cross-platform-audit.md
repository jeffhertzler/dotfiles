# Cross-platform configuration audit

Last audited: 2026-07-28

Source baseline: `b300c98` on `normalize/multi-platform`

Profiles: native Windows/Git Bash, Ubuntu WSL, macOS, EndeavourOS/Arch

This is the authoritative current-state report for the multi-platform Chezmoi
configuration. It replaces the migration-era divergence inventory. The old
inventory was useful while decisions were unresolved, but it mixed obsolete
snapshots, completed decisions, rollback history, and current policy.

## Executive summary

The configuration is healthy and substantially unified. Each of the four
supported machines has a clean source clone at the audited baseline, and all
four passed:

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

The remaining work is cleanup rather than recovery. Open decisions are limited
to dormant Mac Jabba state and the Windows ble.sh update policy. Broader Mise
adoption and native-Windows Go remain explicitly deferred.

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

`.chezmoiignore` currently provides a deny-by-default allowlist for WSL, macOS,
and Windows. It was an appropriate migration scaffold, but it now repeats most
of the shared application set in nested conditions. Arch mostly inherits the
source tree and then excludes other profiles' shell files.

The end state should be easier to read:

1. All four supported profiles receive the shared base by default.
2. Each profile receives only its own shell overlay.
3. Mac/Arch-only workstation applications are excluded elsewhere.
4. Arch-only legacy tmux/Workmux files are excluded elsewhere.
5. WSL/Mac tunnel implementations remain profile-specific.
6. Generic Linux and unsupported systems remain denied by default.

This is a cleanup recommendation, not evidence of incorrect rendered targets.

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

### Required conditionals

These differences should remain conditional:

- Windows command strings that Herdr or LazyGit launch through `cmd.exe`
- Windows Git Bash shell selection and Herdr preview update channel
- OS-native open commands (`start`, `open`, and `xdg-open`)
- Windows Neovim executable/path handling and Oxfmt launcher
- WSL and macOS tunnel implementations
- Platform shell overlays
- Arch-only tmux/Workmux legacy configuration
- Arch-only Ultralight Worktrunk hooks and symlink seeder
- Mac/Arch-only workstation applications
- Optional integrations guarded by executable or file availability

### Conditionals removed during this cleanup

- Git configuration is now a plain shared source file.
- Herdr's desired plugin inventory no longer repeats identical profile arrays.
- `.chezmoiignore` now describes a shared base with narrow exclusions.
- Portable aliases formerly repeated in Unix overlays now live in shared shell
  layers with capability or profile guards.

## Tool installation and provenance

This table records the audited executable source. It is descriptive rather than
a promise that Chezmoi installs every dependency.

| Tool/group | Windows | WSL | macOS | Arch |
| --- | --- | --- | --- | --- |
| Git / Git LFS | WinGet / bundled | apt | Apple Git / Homebrew LFS | pacman |
| GitHub CLI | WinGet | apt | Homebrew | pacman |
| Chezmoi | WinGet | Mise | Homebrew | pacman |
| Neovim | WinGet | direct release | Homebrew | local AppImage |
| LazyGit | WinGet | Mise | Homebrew | pacman |
| Herdr | official preview installer | direct release | direct release | direct/local |
| OpenCode | official installer | official installer | official installer | official installer |
| Pi | Mise | Mise | Volta | Volta |
| Node | WinGet | Mise | Volta | Volta |
| Bun | not required by the Windows title-sync fork | official installer, 1.3.14 | official installer, 1.3.14 | official installer, 1.3.14 |
| Python | Windows packages | Mise | Homebrew | pacman |
| Go | not installed | Mise | custom `~/.go` | custom `~/.go` |
| Worktrunk | WinGet | Cargo | Homebrew | Cargo under `~/.local` |
| Starship | WinGet | direct release | Homebrew | pacman |
| Atuin | WinGet | direct release | Homebrew | pacman |
| LazyJira | not installed | not installed | trusted Homebrew formula | not installed |
| Bat | WinGet | apt | Homebrew | pacman |
| Yazi | WinGet | direct release | Homebrew | pacman |
| jq / zoxide | WinGet | direct release | Homebrew | pacman |
| fzf / fd / ripgrep | WinGet | apt/direct packages | Homebrew | pacman |
| LLVM | WinGet | system packages as needed | Homebrew/system as needed | pacman/system as needed |
| 1Password CLI | available | apt | available | pacman |

### Notable version and manager drift

- Windows retains the standalone Python 3.12 installation for `python`, `pip`,
  and `pip3`; the newer Python Install Manager owns `python3` and makes 3.14 the
  `py` default. This is documented command ownership rather than a PATH fault;
  neither runtime should be removed without checking the native Python app.
- WSL now sets a Mise discovery ceiling at its Linux home and the mounted
  Windows home, preventing native Windows global configuration from leaking
  into WSL projects.
- macOS now uses Homebrew for Bat, `fd`, and ripgrep; their obsolete Cargo
  copies have been removed.
- macOS package drift is resolved: obsolete Cargo copies, Workmux, the old
  wkhtmltopdf cask/tap, deprecated Homebrew taps, and orphaned `icu4c@75` have
  been removed. LazyJira remains intentionally installed and only its specific
  third-party formula is trusted. `brew doctor` is clean.
- macOS Bun has been upgraded from 1.0.0 to 1.3.14 through its official
  self-updater.
- Arch uses Volta for Node, npm, npx, and Pi. The unused Hermes installation,
  its private runtime, and its command shims have been removed.
- Worktrunk is aligned at 0.69.2 on all four profiles.
- Windows ble.sh remains a release-tree installation under
  `~/.local/share/blesh`; a Windows-only Chezmoi bootstrap installs the upstream
  nightly build when that tree is missing and never replaces an existing copy.
- Atuin remains installed on macOS for local shell history, but its unused and
  failing background daemon service has been removed. Automatic sync remains
  disabled in the shared configuration.
- Broader Mise adoption remains deliberately deferred. It may eventually provide
  a consistent programming-language manager without needing to own standalone
  applications.

## Application findings

### Git and GitHub

- New GitHub operations prefer SSH on all four platforms.
- Machine-local credential helpers remain necessary for legacy HTTPS remotes.
- The same RSA key is used across the four setups and is registered with GitHub.
- Credentials, account records, SSH config, and known-host policy are correctly
  excluded from the repository.
- Git configuration is a plain shared Chezmoi source file.

### Neovim

- The shared LazyVim tree works on all four profiles.
- TypeScript and Python were interactively verified; Go tooling is guarded when
  Go is unavailable.
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
| Archive helper | No | No | No | Yes |

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
- `nvu` has one Linux/x86-64 definition in the common shell layer.
- `ha` and `hat` have one WSL/macOS definition in the templated Zsh layer.
- The unused `gou` curl-to-shell installer alias has been removed. Go upgrades
  remain the responsibility of each machine's declared runtime owner.
- Greenlight's duplicate `frontend/settings` pull has been removed.
- Greenlight repositories use machine-local path-scoped Git identity includes;
  `gggm` no longer mutates global identity while running `good morning`.

## Cleanup candidates

These candidates were previewed and completed individually:

1. **Complete:** simplify `.chezmoiignore` to a shared-base model.
2. **Complete:** convert the shared Git config template to a plain source file.
3. **Complete:** remove the empty Yazi keymap.
4. **Complete:** remove the stale Neoconf file.
5. **Complete:** resolve contradictory LazyVim Refactoring declarations.
6. **Complete:** reduce Atuin to intentional non-default settings.
7. **Complete:** remove unused Yazi and Bat theme files.
8. **Complete:** portable aliases and Greenlight helpers are deduplicated, and
   `gggm` relies on path-scoped Git identity instead of global mutation.
9. **Complete:** retire the legacy Go installer alias.

The Arch tmux and Workmux sources are not dead configuration. They are retained
legacy by explicit policy and should not be removed as part of general cleanup.
Arch Jabba actively selects Temurin 11 and retains JDKs 8, 17, and 21. The
shared Mac/Arch `.profile` is the POSIX login-shell fallback for Volta; Zsh uses
the equivalent `.zshenv` setup.

## Installation gaps and optional enhancements

Optional:

- Decide whether the Windows ble.sh bootstrap should remain install-only or
  gain an explicit update policy. It currently preserves the working version.
- Install Go on native Windows if Windows-local Go development becomes useful.
- Adopt Mise for programming-language runtimes on more profiles after a separate
  design pass.

## Recommended cleanup sequence

Each step should be previewed narrowly and verified on all affected profiles.

1. **Complete:** `dotfiles-doctor` reports required tools, resolved
   versions/paths, Windows environment variables, Chezmoi state, Herdr plugin
   sources, and optional Yazi dependencies on all four profiles.
2. **Complete:** `.chezmoiignore` now expresses a shared supported-profile base
   with narrow exclusions, and the identical Git configuration is a plain file.
3. **Complete:** the retired Neoconf file and empty Yazi keymap are removed; the
   stale Refactoring extra is gone while the explicit plugin disable remains.
4. **Complete:** Atuin contains only intentional settings; redundant Bat/Yazi
   themes and duplicate `nvu`, `ha`, `hat`, and Greenlight pull logic are gone.
5. **Complete:** portable Worktrunk layout/schema settings are shared; the
   Unix-only Ultralight hooks remain on Arch, and all four profiles run 0.69.2.
6. **Complete:** all four plugins are desired everywhere; monthly reconciliation
   updates Unix upstream installs and Windows private branches while preserving
   explicit review for public-upstream merges and plugin removal.
7. **Complete:** WSL Mise discovery is isolated from Windows; Arch uses Volta
   instead of Hermes; Bun is current; Windows can bootstrap ble.sh; and macOS
   package ownership, obsolete taps, and retained LazyJira trust are clean.
8. **Skipped by policy:** Yazi's existing preview coverage is sufficient; do
   not add optional media, PDF, image, archive, `chafa`, or `resvg` dependencies
   merely for cross-platform parity.
9. **Complete:** Windows, WSL, macOS, and Arch have clean source worktrees,
   empty Chezmoi diffs/status, successful verification, and zero doctor
   failures. Windows retains four expected warnings until parent applications
   restart and inherit its persistent Yazi, Bat, and Worktrunk environment.

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
