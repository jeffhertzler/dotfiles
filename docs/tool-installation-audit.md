# Tool installation ownership audit

Status: inventory complete; ownership review in progress

Snapshot date: 2026-07-28

Profiles: native Windows, WSL Ubuntu 26.04, macOS, Arch Linux

This audit is the input to the future WinGet, APT, Homebrew, and pacman
manifests. The manifests must describe the ownership decisions made here; they
must not preserve every package that happens to be installed today.

The inventory covers every user-selectable/top-level package, every Mise tool,
and every observed manual executable channel. Transitive OS libraries and
framework packages are still covered: their native package manager owns them,
but they are not promoted into hand-maintained manifest entries.

## Classification

- **Native**: keep in WinGet, APT, Homebrew, or pacman. This is the normal owner
  for desktop applications, shells, system integration, drivers, libraries,
  and stable standalone utilities available on every relevant platform.
- **Mise**: keep in the shared or profile-specific Mise inventory. This is the
  normal owner for programming runtimes, project-versioned tools, and portable
  developer CLIs for which one consistent owner is valuable.
- **Official**: retain the vendor installer or updater because a preview
  channel, application integration, or lack of a suitable manager warrants it.
- **Project-local**: install with the project that consumes the tool instead of
  maintaining global ecosystem state.
- **Dependency/system**: leave installed and let the native package manager
  decide whether it is required. Do not list it as a desired top-level tool.
- **Review**: the current owner or continued need is not yet approved.

## Cross-platform ownership matrix

| Tool or group | Current owner | Preliminary recommendation | Status |
| --- | --- | --- | --- |
| Git, Git LFS, GitHub CLI | native on all profiles | Native | correct |
| 1Password CLI | native/vendor repository | Native | correct |
| Mise itself | WinGet / official WSL install / Homebrew / pacman | Native or official bootstrap | correct exception; Mise cannot be its only bootstrap owner |
| Neovim nightly | Mise on all profiles | Mise | correct |
| Node, Python, Go, Bun | Mise on all profiles | Mise | correct |
| Java 11/17 and Maven | Mise on macOS and Arch | Mise | correct; macOS also has duplicate JDK casks |
| Pi, Neovim Node host, pynvim | Mise ecosystem backends | Mise | correct |
| Worktrunk, Dust | Mise `aqua:` on all profiles | Mise | correct; Arch also has duplicate pacman Dust |
| OpenCode | official installer on all profiles | Official | correct by explicit policy |
| Herdr | official release/preview installer | Official | correct |
| Bat, fzf, fd, ripgrep | native on all profiles | Native | correct; repository version lag is acceptable |
| Starship, Atuin, Yazi, jq, zoxide | Mise `aqua:` on all profiles | Mise | correct; native top-level copies retired |
| LazyGit | Mise `aqua:` on all profiles | Mise | correct; native and superseded Mise copies retired |
| Tree-sitter CLI | Mise `aqua:` 0.26.11 on all profiles | Mise | correct; one pinned Neovim build tool |
| Posting | Mise `pipx:` on macOS and Arch | Mise | correct on the two profiles where it is used |
| LazyDocker | Homebrew on macOS; pacman on Arch | Native | correct; not needed elsewhere |
| Delta | Homebrew on macOS; pacman on Arch; no Git pager config | remove unless still wanted interactively | review |
| AWS CLI, kubectl, k9s | native where used | Native | correct unless project pinning becomes necessary |
| Terraform | pacman on Arch | Mise/project version | migrate if retained |
| Julia | pacman on Arch | Mise if retained | migrate if retained |
| Deno | WinGet on Windows; Homebrew dependency on macOS | Mise only if directly used | review; do not manage macOS's dependency copy |
| Odin | WinGet on Windows | Mise if actively developed; otherwise remove | review |
| Playwright library and CLI | Arch packages | Project-local by default | review actual global use before migration/removal |

## Native Windows

### Correct owner or expected exception

- WinGet developer tools: `AgileBits.1Password.CLI`, `sharkdp.bat`,
  `twpayne.chezmoi`, `sharkdp.fd`, `junegunn.fzf`, `Git.Git`, `GitHub.cli`,
  `LLVM.LLVM`, `jdx.mise`, `FiloSottile.mkcert`, `Microsoft.PowerShell`, and
  `BurntSushi.ripgrep.MSVC`.
- Mise tools: Bun, Go, Neovim nightly, Node LTS, Python, uv, Worktrunk, Dust,
  Starship, Atuin, Yazi, jq, zoxide, LazyGit, Tree-sitter CLI, Pi, Neovim's
  Node host, and pynvim.
- Official/manual exceptions: Herdr preview and OpenCode.
- Dotfile-owned launchers in `~/.local/bin`: Agent Review, doctor, Herdr popup
  helpers, LazyGit/Yazi Neovim bridges, and the research-video launcher.

The former WinGet Starship, Atuin, Yazi, jq, zoxide, and LazyGit packages are
gone. Tree-sitter's superseded Mise GitHub backend is also gone.

### Native workstation applications

These belong to WinGet or their vendor installer if retained. They should be
separated from the developer CLI manifest so a bootstrap can select a
`windows-workstation` role:

- 1Password, Arc, Helium, Zen Browser, VS Code, JetBrains Toolbox
- Beekeeper Studio, MongoDB Compass, NoSQLBooster, TablePlus, Yaak
- CrystalDiskInfo, PowerToys, Windows Terminal, WSL, Ubuntu
- Focusrite Control, SteelSeries GG, PlayStation Accessories
- REAPER, Zoom, Teams, OneDrive, Tailscale, Syncthing
- Steam, EA app, Ubisoft Connect, Path of Building, and PoE2 Path of Building
- Odin and Deno are listed here by WinGet today but are runtime review items,
  not desktop applications.

Visual C++ redistributables, Windows App Runtime/UI frameworks, DirectX,
GameInput, Edge, .NET desktop runtimes, NVIDIA PhysX, ViGEm, and Epic Online
Services are dependency/system state. They must not become explicit manifest
entries merely because `winget list` can identify them.

### Windows review queue

- Decide whether the database/API client overlap is intentional: Beekeeper,
  Compass, NoSQLBooster, TablePlus, and Yaak.
- Decide whether Arc and Zen are still desired alongside Helium.
- Move Deno and Odin to Mise if they are active development runtimes; otherwise
  leave them out of the eventual manifest and remove them separately.
- Package updates shown by WinGet are maintenance work, not ownership changes.

## WSL Ubuntu 26.04

### Correct owner

- APT development/shell tools: `1password-cli`, `bat`, `build-essential`,
  `fd-find`, `fzf`, `gh`, `git-lfs`, `libsqlite3-dev`, `mosh`, `ripgrep`,
  `sqlite3`, `unzip`, and `zsh`.
- APT base/system packages: Bash, Dash, init, hostname, ncurses, archive and
  filesystem utilities, `ubuntu-minimal`, and `ubuntu-wsl`.
- Mise tools: Bun, Go, Neovim nightly, Node LTS, Python, uv, Chezmoi,
  LazyGit, Tree-sitter CLI, Worktrunk, Dust, Pi, Neovim's Node host, pynvim,
  Starship, Atuin, Yazi, jq, and zoxide.
- Official/manual exceptions: Mise bootstrap, Herdr, OpenCode, and the
  WSL-to-Windows PTY bridge.
- Dotfile-owned scripts in `~/.local/bin` are expected and managed by Chezmoi.

`coreutils`, `coreutils-from-uutils`, `gnu-coreutils`, and `rust-coreutils` are
part of Ubuntu 26.04's GNU/uutils transition. Current `/usr/bin/ls`, `cp`, `mv`,
and `cat` are owned by `coreutils-from-uutils`; these packages require a
separate base-OS check and must not be pruned as ordinary duplicate CLIs.

The superseded standalone Starship, Atuin, Yazi, `ya`, jq, zoxide, and
`atuin-update` executables are recoverable from WSL's Trash. LazyGit and
Tree-sitter's former Mise GitHub backends are retired.

## macOS

### Current native inventory

- Shell/general CLI: Bash, Bat, btop, curl, eza, fd, fzf, gawk, ripgrep,
  tealdeer, wget, and Git Delta pending review.
- Git/dev tooling: GitHub CLI, Git LFS, mkcert, CMake, Ninja, GCC, LuaJIT,
  LuaRocks, and zlib.
- DevOps: AWS CLI, k9s, LazyDocker, and Orbstack.
- Media/preview tools: aria2, ffmpeg, ImageMagick, librsvg, and yt-dlp.
- Applications/casks: 1Password CLI, Claude desktop, Claude Code, MongoDB
  Compass, OpenCode Desktop, and Orbstack.
- LazyJira remains an explicitly trusted third-party formula while it is being
  evaluated.

Homebrew dependencies such as `nss` and libraries pulled by the leaves above
remain Homebrew-owned and should not be manually listed.

### Correct Mise owner

Bun, Go, Java 11/17, Maven, Neovim nightly, Node LTS, Python, uv, Worktrunk,
Dust, Starship, Atuin, Yazi, jq, zoxide, LazyGit, Tree-sitter CLI, Posting, Pi,
Neovim's Node host, and pynvim.

### macOS review queue

- Homebrew casks `temurin@11` and `temurin@17` duplicate Mise Java. The
  `temurin@8` cask has no matching approved project requirement and is Intel
  under Rosetta. Verify no GUI/system consumer needs registered JDKs, then
  remove all three casks if shell/project Java is the only requirement.
- Delta is installed but is not configured as Git's pager. Remove it unless an
  interactive use remains.
- `dnsmasq`, `nushell`, and the broad build stack are retained for now but need
  a use review before being promoted to the manifest.

## Arch Linux

### Current native/system inventory

- Base, boot, storage, network, audio, firmware, GPU, Wayland/Xorg, filesystem,
  package-maintenance, and EndeavourOS packages remain pacman-owned. Examples
  include `base`, `amd-ucode`, `efibootmgr`, `btrbk`, `docker`, `tailscale`,
  `alsa-utils`, `bluez-utils`, NVIDIA packages, filesystem utilities, and EOS
  hooks/keyrings.
- Shell/general CLI: Bat, btop, eza, Git Delta, Git LFS, GitHub CLI, and tldr
  pending the Delta decision. Pacman zoxide remains installed as a dependency
  of `sesh-bin`, while the interactive command resolves Mise.
- DevOps and data tools: AWS CLI plus Session Manager, kubectl, k9s,
  LazyDocker, Docker Compose, grpcurl, Helm docs, MariaDB clients, mkcert,
  Terraform pending migration, and database/API TUIs pending use review.
- Workstation applications: Ghostty, Steam, Moonlight, Cursor, Codex, and
  gaming-session packages remain native/AUR if retained.
- Arch-only tmux/Workmux state and its supporting tools remain intentional
  legacy configuration.

### Correct Mise owner

Bun, Go, Java 11/17, Maven, Neovim nightly, Node LTS, Python, uv, Worktrunk,
Dust, Starship, Atuin, Yazi, jq, zoxide, LazyGit, Tree-sitter CLI, Posting,
Harlequin, Pi, Neovim's Node host, and pynvim.

### Arch review queue

- Remove pacman `dust` after confirming the Mise executable; it is a direct
  duplicate.
- Remove `bottom`; it is explicitly unused and btop is the preferred monitor.
- Remove `asdf-vm` after confirming no project invokes it; Mise supersedes it.
- Remove inactive, unconfigured Mise Node 20.19.2 after the remaining Volta
  project review confirms it is not needed.
- Migrate Julia and Terraform to Mise if retained.
- Treat global `playwright` and `playwright-cli` as project-local unless a
  specific shared automation consumer is identified.
- Delta is installed but no pager configuration was found. Remove it unless an
  interactive use remains.
- Review overlapping monitors and disk tools: btop is preferred, while
  `glances`, `htop`, `gdu`, and `duf` may now be redundant. Dust remains the
  preferred directory-size tool.
- Review overlapping database/API TUIs: `atac`, `jwt-ui`, `rainfrog`,
  `lazysql`, Posting, and Harlequin.
- Review old or specialized explicit tools before manifesting them: Julia,
  Tectonic, `wkhtmltopdf-static`, `python2-bin`, `reiserfsprogs`,
  `fga-bin`, `crush-bin`, `rtk`, `sesh-bin`, Stripe CLI, ngrok, and LazyJira.

## Review order before manifests

1. Remove only verified duplicates/dead leaves: Arch pacman Dust/bottom/asdf,
   macOS Temurin casks, and unused Delta. The WSL portable-CLI leftovers are
   already recoverable from Trash.
2. Decide language/project tooling: Deno, Odin, Julia, Terraform, and global
   Playwright.
3. Review overlapping workstation/TUI tools with the user; installed state is
   not sufficient evidence of intent.
4. Generate role-aware native manifests from the accepted `Native` entries.
   Mise remains declared in its existing shared configuration.
5. Add check/plan commands and explicit bootstrap commands. Ordinary
   `chezmoi apply` must not silently install or remove native packages.
