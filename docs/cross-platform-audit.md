# Cross-platform configuration audit

Last audited: 2026-07-28

Source baseline: `052ba01` on `normalize/multi-platform`

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

The remaining work is cleanup rather than recovery. The biggest opportunities
are simplifying the Chezmoi allowlist, removing confirmed dead configuration,
making installation drift visible, and defining an explicit Herdr plugin update
policy.

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
| Herdr plugins | Three private compatibility clones linked locally | Three upstream plugins | Three upstream plugins | Three upstream plugins plus one unmanaged extra |
| Tunnel | None | systemd user-service implementation | SSH ControlMaster implementation | None |
| LazyDocker/Posting | None | None | Managed | Managed |
| tmux/Workmux | None | tmux installed, config not managed | executables may remain, config retired | Managed as intentional legacy |
| Worktrunk user config | Plugin bridge only | Plugin bridge only | Plugin bridge only | Full user config and seed helper |

### Required conditionals

These differences should remain conditional:

- Windows command strings that Herdr or LazyGit launch through `cmd.exe`
- Windows Git Bash shell selection and Herdr preview update channel
- OS-native open commands (`start`, `open`, and `xdg-open`)
- Windows Neovim executable/path handling and Oxfmt launcher
- WSL and macOS tunnel implementations
- Platform shell overlays
- Arch-only tmux/Workmux legacy configuration
- Mac/Arch-only workstation applications
- Optional integrations guarded by executable or file availability

### Conditionals that can probably disappear

- `dot_config/git/config.tmpl` only emits shared behavior for all four supported
  profiles and can become a plain file.
- The repeated profile arrays in `.chezmoidata/herdr-plugins.yaml` are identical
  for every desired plugin.
- Much of `.chezmoiignore` repeats the same shared allowlist for Windows, WSL,
  and macOS.
- Duplicate portable aliases in more than one Unix overlay can move into the
  shared shell file after a narrow compatibility check.

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
| Node | WinGet | Mise | Volta | local Hermes shim shadows Volta |
| Python | Windows packages | Mise | Homebrew | pacman |
| Go | not installed | Mise | custom `~/.go` | custom `~/.go` |
| Worktrunk | WinGet | Cargo | Homebrew | direct/local |
| Starship | WinGet | direct release | Homebrew | pacman |
| Atuin | WinGet | direct release | Homebrew | pacman |
| Bat | WinGet | apt | Homebrew plus old Cargo copy | pacman |
| Yazi | WinGet | direct release | Homebrew | pacman |
| jq / zoxide | WinGet | direct release | Homebrew | pacman |
| fzf / fd / ripgrep | WinGet | apt/direct packages | mixed Homebrew and old Cargo | pacman |
| LLVM | WinGet | system packages as needed | Homebrew/system as needed | pacman/system as needed |
| 1Password CLI | available | apt | available | pacman |

### Notable version and manager drift

- Windows has both `python` 3.12 and `python3` 3.14 resolution. This may be
  intentional, but the command distinction should be documented or normalized.
- WSL can discover the native Windows Mise config when launched beneath a
  `/mnt/c/Users/...` working directory. It currently duplicates only the Pi pin,
  but this is unintended cross-environment coupling.
- macOS still has old Cargo-installed copies of tools also managed elsewhere.
  Old Cargo `fd` and `rg` currently win command resolution because Homebrew
  versions of those two are absent.
- macOS Homebrew reports an obsolete/untrusted `loadstar81/wkhtmltopdf` tap.
- Arch's `node` and `npm` resolve through Hermes Node 22 shims even though Volta
  owns Node 24. This is the clearest active toolchain ambiguity.
- Arch Worktrunk is one release behind the other machines at the audited
  snapshot.
- Windows ble.sh is manually present under `~/.local/share/blesh`; no package or
  bootstrap mechanism currently declares it.
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
- The shared Git template no longer appears to require templating.

### Neovim

- The shared LazyVim tree works on all four profiles.
- TypeScript and Python were interactively verified; Go tooling is guarded when
  Go is unavailable.
- LazyGit, Yazi, and Agent Review can target an existing Neovim instance.
- `lazy-lock.json` is intentionally unmanaged runtime state.
- Confirmed cleanup candidates:
  - `dot_config/nvim/dot_neoconf.json` configures retired Neoconf/Neodev
    behavior even though LazyDev replaced it.
  - `dot_config/nvim/lazyvim.json` enables the Refactoring extra while
    `lua/plugins/disabled.lua` disables `refactoring.nvim`.

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

Confirmed Yazi cleanup candidates:

- `dot_config/yazi/keymap.toml` is empty.
- Two alternate theme files are deployed but never selected.

### Herdr and plugins

Shared behavior now includes directional pane movement, pane resizing,
full-height layouts, Worktrunk access, popup picking, and LazyGit/Yazi bridges.
Windows uses private compatibility forks for the three desired plugins; Unix
profiles use upstream repositories.

The desired inventory contains:

- `edi.layout-tools`
- `herdr-splits`
- `worktrunk`

Remaining policy gaps:

- Unix reconciliation installs and enables missing plugins but does not update
  existing checkouts or remove extras.
- Windows reconciliation links local clones but does not verify that each clone
  is on the documented branch/ref/commit.
- Arch has `herdr-splits` 0.5.0 while the other profiles have 0.5.1.
- Arch also has an unmanaged `rjyo.window-title-sync` plugin. Decide whether it
  should become desired everywhere, remain an explicit Arch extra, or be
  removed.

### Shell and small tools

- Atuin works across Bash and Zsh, including the corrected Git Bash Ctrl-R
  binding through ble.sh.
- The checked-in Atuin file now contains only the intentional local-history,
  session-up-arrow, style, Enter-accept, and record-sync settings.
- Bat uses its bundled Catppuccin Mocha theme on all four profiles; redundant
  checked-in Bat themes and two unused Yazi theme variants were removed.
- `nvu` has one Linux/x86-64 definition in the common shell layer.
- `ha` and `hat` have one WSL/macOS definition in the templated Zsh layer.
- The `gou` alias executes an old `git.io` installer and should be reconsidered
  now that Go is manager-owned on some systems.
- Greenlight's duplicate `frontend/settings` pull has been removed.
- Greenlight's `gggm` mutates global Git email and is brittle compared with a
  repository-local identity mechanism.

## Confirmed cleanup candidates

These changes are low-risk once previewed individually:

1. Simplify `.chezmoiignore` to a shared-base model.
2. Convert `dot_config/git/config.tmpl` to a plain Chezmoi source file.
3. Remove the empty Yazi keymap.
4. Remove the stale Neoconf file.
5. Resolve the contradictory LazyVim Refactoring enable/disable declarations.
6. Reduce Atuin configuration to intentional non-default settings.
7. Remove unused Yazi and Bat theme files, unless they are deliberately kept as
   ready alternatives.
8. Deduplicate portable shell aliases and fix the two Greenlight helper issues.
9. Replace or retire the legacy Go installer alias.

The Arch tmux and Workmux sources are not dead configuration. They are retained
legacy by explicit policy and should not be removed as part of general cleanup.
Likewise, `.profile` and Jabba have not yet been proven dead.

## Installation gaps and optional enhancements

Required or worth correcting:

- Align Arch's Worktrunk and `herdr-splits` versions.
- Resolve whether Arch uses Hermes or Volta as the actual Node owner.
- Prevent WSL from unintentionally consuming native Windows Mise configuration.
- Clean obsolete macOS Cargo duplicates and the stale Homebrew tap.
- Make Windows ble.sh installation reproducible if Git Bash remains a supported
  first-class environment.

Optional:

- Add Yazi media/PDF/archive preview dependencies where those previews are
  genuinely useful.
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
5. Decide the Worktrunk configuration boundary, then align the Arch binary.
6. Define Herdr plugin update, version, ref-verification, and extra-plugin
   policy.
7. Resolve package-manager drift on macOS, Arch, and WSL.
8. Add optional Yazi preview tools only where desired.
9. Run `chezmoi diff`, narrow applies, `chezmoi verify --exclude=dirs`, and
   `chezmoi status --exclude=dirs` on Windows, WSL, macOS, and Arch before
   merging `normalize/multi-platform`.

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
