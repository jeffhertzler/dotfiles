# Dotfiles

`sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jeffhertzler`

## Machine profiles

Chezmoi detects one of four supported profiles:

- `arch`: Arch Linux hosts
- `wsl`: Linux running under Windows Subsystem for Linux
- `macos`: macOS
- `windows`: native Windows

All four supported profiles receive a shared application base plus narrowly
scoped shell, launcher, and workstation differences. Generic Linux and unknown
platforms remain denied by default; supported profiles use the shared-base
selection documented in the
[cross-platform audit](docs/cross-platform-audit.md).

## Shell layout

- `.config/shell/common.sh` contains dependency-free editor settings and aliases
  shared by Bash and Zsh.
- WSL, macOS, and Arch render the same Zsh baseline plus their respective
  `.wsl.zsh`, `.mac.zsh`, or `.arch.zsh` profile overlay.
- Native Windows manages `.bash_profile` and `.bashrc` for Git Bash.

Machine-local SSH configuration and credentials are intentionally not managed.

## Package bootstrap

The deliberately small native package manifests live in
[`packages`](packages/README.md). They restore the shell/editor foundation and
host-role essentials without snapshotting every installed application or OS
dependency. Shared runtimes and portable CLIs remain declared through Mise.

## Health check

Run `dotfiles-doctor` from any supported shell for a read-only report covering
required tools, resolved versions and paths, Git and Chezmoi state, Herdr
plugins, and optional Yazi preview support. It exits nonzero for required or
managed-state failures; optional capabilities are reported without failing the
check.

## Git layout

Portable identity, defaults, and global ignores live in `.config/git`. Profile
conditions add only integrations installed on that system. Optional machine-only
settings belong in the unmanaged `~/.config/git/local.config` file.

## LazyGit layout

All supported profiles set `XDG_CONFIG_HOME` to `~/.config`, manage one
`.config/lazygit/config.yml`, and use the same custom Neovim bridge. Unix
invokes the bridge directly; native Windows wraps it with Git Bash because
LazyGit launches editor commands through `cmd.exe` there.
