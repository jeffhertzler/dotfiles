# Dotfiles

`sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jeffhertzler`

## Machine profiles

Chezmoi detects one of four supported profiles:

- `arch`: Arch Linux hosts
- `wsl`: Linux running under Windows Subsystem for Linux
- `macos`: macOS
- `windows`: native Windows

Arch and macOS retain the existing Unix configuration while normalization is
in progress. WSL and native Windows begin deny-by-default and will gain managed
files one reviewed layer at a time.

## Shell layout

- `.config/shell/common.sh` contains dependency-free editor settings and aliases
  shared by Bash and Zsh.
- Arch and macOS render the established Unix Zsh configuration plus their
  respective `.arch.zsh` or `.mac.zsh` profile overlay.
- WSL renders a lightweight Zsh baseline plus its profile helpers in `.wsl.zsh`.
- Native Windows manages `.bash_profile` and `.bashrc` for Git Bash.

Machine-local SSH configuration and credentials are intentionally not managed.
