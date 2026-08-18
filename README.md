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
platforms remain denied by default.

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
required tools, resolved versions and paths, Git and Chezmoi state, Arch Mise
bootstrap convergence, Herdr plugins and integrations, and optional Yazi preview
support. It exits nonzero for required or managed-state failures; optional
capabilities are reported without failing the check.

## Tests

Run TypeScript tests from the repository root with `tsx`, which supplies the
TypeScript loader and resolves the runtime dependencies used by Pi extensions:

```sh
tsx --test tests/herdr-subagent.test.ts
```

Use `tsx --test tests/*.test.ts` to run the complete TypeScript test suite.
Do not use plain `node --test` for `.ts` test files.

The managed Atuin extension is an exact snapshot of `atuin hook install pi`, not
locally customized. Its test generates the extension from the installed Atuin
release and compares it byte-for-byte, while `dotfiles-doctor` performs the same
check against the deployed extension. When Atuin changes its bundled extension,
regenerate the snapshot in a temporary home and review the diff before applying
it through chezmoi.

## Git layout

Portable identity, defaults, and global ignores live in `.config/git`. Profile
conditions add only integrations installed on that system. Optional machine-only
settings belong in the unmanaged `~/.config/git/local.config` file.

## LazyGit layout

All supported profiles set `XDG_CONFIG_HOME` to `~/.config`, manage one
`.config/lazygit/config.yml`, and use the same custom Neovim bridge. Unix
invokes the bridge directly; native Windows wraps it with Git Bash because
LazyGit launches editor commands through `cmd.exe` there.
