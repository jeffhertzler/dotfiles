# Native package bootstrap

The manifests in this directory and the managed Mise config describe the small
native package layer needed to restore the shell, editor, and remote-development
environment. They are deliberately not exports of everything installed on the
current machines.

Arch packages, shared programming runtimes, and portable CLIs are declared in
`dot_config/mise/config.toml.tmpl`. Herdr and OpenCode retain their official
installers. Desktop applications, games, hardware utilities, optional preview
tools, experimental TUIs, project-only tools, and transitive OS dependencies
are outside this layer.

All commands below are additive. None removes packages that are not listed.

## Windows

The DSC configuration covers the native Git Bash/development foundation plus
the Windows host components required by this setup:

```powershell
winget configure test --file packages/windows.dsc.yaml
winget configure --file packages/windows.dsc.yaml --accept-configuration-agreements
```

## WSL Ubuntu

Start from the normal Ubuntu WSL image. The GitHub CLI and 1Password APT
repositories must be configured before installing the list on a fresh image.

```bash
grep -Ev '^\s*(#|$)' packages/wsl-apt.txt |
  xargs sudo apt-get install
```

Mise is bootstrapped with its official installer; the managed Mise config then
installs Chezmoi and the shared tool set.

## macOS

```bash
brew bundle check --file packages/Brewfile
brew bundle --file packages/Brewfile
```

The Brewfile intentionally excludes the broad compiler/media stack and
experimental applications currently installed on the Mac.

## Arch

Start from the normal EndeavourOS installation so it continues to own the base,
boot, driver, filesystem, audio, and desktop package closure. Bootstrap Mise
with its official installer so it can update independently with
`mise self-update` instead of waiting for the Arch package:

```bash
curl https://mise.run | sh
```

After Chezmoi has applied the managed Mise config, preview and converge the
Pacman package layer and shared Mise tools:

```bash
mise bootstrap plan
mise bootstrap --yes --update
```

The AUR package remains a separate additive step:

```bash
grep -Ev '^\s*(#|$)' packages/arch-aur.txt |
  xargs yay -S --needed --
```

The Mise declarations restore the user-facing remote development layer, not a
bare-metal Arch installation or every project-specific AUR package. The AUR
list contains only the 1Password CLI needed for optional secret bootstrap.
