# Gaming Flatpak NVIDIA maintenance (Arch workstation only)

## Existing update path and failure

The workstation uses Yay, which invokes Pacman for both repository upgrades and
AUR package installations. `/var/log/pacman.log` records the October 26, 2026
`nvidia-580xx-utils` / DKMS upgrade from 580.178.04 to 580.196.07 in separate
Pacman transactions. The repository's [bootstrap instructions](../README.md#arch)
also use Pacman; there is no managed system-update wrapper. No custom ALPM hooks
were installed when this prevention was prepared.

Gaming's per-user Flatpak GL extension did not follow that host upgrade.
Installing the exact matching GL extension and relaunching only Punktfunk
restored the GTX 1070 renderer and populated library, with the app branch/commit
unchanged. App maintenance is not the right place to couple host-driver updates.

## Scope

`95-gaming-flatpak-nvidia.hook` runs after successful install/upgrade transactions
containing **`nvidia-580xx-utils`**, the sole trigger package (including Yay,
reinstalls, and downgrades). It does not require a wrapper, timer, service, app
launcher change, or Pi job change.

The helper computes the union of:

- installed userspace version from `pacman -Q nvidia-580xx-utils`, stripping
  package epoch/release; and
- actually loaded kernel module version from `/sys/module/nvidia/version`, if
  loaded. It deliberately does not use `nvidia-smi` or `modinfo`.

It ensures missing exact
`runtime/org.freedesktop.Platform.GL.nvidia-VERSION/x86_64/1.4` refs in **gaming's
user installation**, from its existing `flathub` remote. Version dots become
hyphens. Before reboot this can mean two versions; neither is removed. Once
both are present, reruns make no changes and need no network.

Only missing refs are installed, with `--no-related --no-deps`. No Flatpak
`update`, `--or-update`, uninstall, remote changes, app branch selection, GL32,
VAAPI, codec, or base-runtime updates occur. Existing refs are not refreshed.
Explicit installs retain Flatpak's default pinning; cleanup is a separate,
manual decision after checking loaded and installed driver versions.

## Security and activation

These are source artifacts, already excluded from Chezmoi by the `packages`
ignore. **Chezmoi apply does not activate them.** Do not point a root Pacman hook
at this user-writable checkout, `~/.local/bin`, or gaming's scripts.

After reviewing the source, have the parent submit these exact commands through
`sudo_task`, with cwd `/home/jeffhertzler/.local/share/chezmoi`:

1. Install the reviewed helper into a root-owned directory:

   ```sh
   /usr/bin/install -D -o root -g root -m 0755 /home/jeffhertzler/.local/share/chezmoi/packages/arch/gaming-flatpak-nvidia.py /usr/local/libexec/gaming-flatpak-nvidia
   ```

2. Activate the hook (install last, so its helper already exists):

   ```sh
   /usr/bin/install -D -o root -g root -m 0644 /home/jeffhertzler/.local/share/chezmoi/packages/arch/95-gaming-flatpak-nvidia.hook /etc/pacman.d/hooks/95-gaming-flatpak-nvidia.hook
   ```

3. Verify current coverage without installing anything:

   ```sh
   /usr/bin/python3 -I /usr/local/libexec/gaming-flatpak-nvidia --check
   ```

The directories `/usr/local`, `/usr/local/libexec`, `/etc/pacman.d`, and
`/etc/pacman.d/hooks` must remain root-owned and not writable by other users.
`install -D` creates missing parent directories with mode 0755. No daemon reload
or reboot is needed to activate the hook; Pacman reads it on the next matching
transaction. Source revisions require re-copying the reviewed files.

The hook invokes the system Python with `-I`, avoiding user Python paths. The
helper uses absolute command paths, a clean environment, no shell, and no
session bus. It reads the host version as root, then permanently drops groups,
GID, and UID to `gaming` **before any Flatpak command or user configuration is
read**. It never invokes Flatpak as root. Per-user data/config/cache directories
are explicitly selected from gaming's passwd home.

## Failures and limits

- Flatpak commands are noninteractive and bounded (20 seconds for listing,
  180 seconds per install, then 10 seconds before forced termination). Failures
  return nonzero and print the failed ref plus a retry command in Pacman's
  output. Inspect hook failures; a post-transaction failure cannot roll back the
  completed host upgrade.
- Offline/missing remote/unpublished NVIDIA runtime failures require a later
  explicit retry. No background retry infrastructure is added. In a reviewed
  privileged step, run:

  ```sh
  /usr/bin/python3 -I /usr/local/libexec/gaming-flatpak-nvidia --sync
  ```

- A driver update still normally requires reboot. Keeping both Flatpak refs
  does not repair native host userspace/kernel mismatches, failed DKMS builds,
  initramfs problems, or already-running app processes. Nothing is restarted.
- This is intentionally specific to the gaming account, `nvidia-580xx-utils`,
  x86_64 GL and branch 1.4. A driver-package-family/architecture/remote change
  requires reviewing this helper and hook; other users and GL32 are not managed.
- Failed Pacman transactions do not run post-transaction hooks. If a partial
  transaction changed drivers, recover Pacman and run the explicit retry.
- Disable by removing only `/etc/pacman.d/hooks/95-gaming-flatpak-nvidia.hook`
  through a reviewed privileged step. This does not remove any installed refs.

## Tests (no privileged or live operations)

```sh
tsx --test tests/flatpak-nvidia-sync.test.ts
/usr/bin/python3 -I tests/flatpak-nvidia-sync_test.py -v
tsx --test tests/*.test.ts
```

The TypeScript test invokes the Python behavioral tests. All commands, identity
changes, and loaded-version reads are mocked; tests do not touch gaming state.
They cover pre-reboot and post-reboot versions, deduplication, idempotence,
downgrades, absent modules, malformed versions, exact install scope, failures,
check-only behavior, privilege-drop ordering, and the root-owned hook boundary.
