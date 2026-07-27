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
