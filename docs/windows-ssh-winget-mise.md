# Windows SSH, WinGet links, and Mise shims

_Investigated 2026-08-21 against host measurements and primary sources._

## Conclusion

The evidence supports this chain:

1. The Windows OpenSSH install script writes an Image File Execution Options `MitigationOptions` value for `sshd.exe` specifically to enable RedirectionGuard. It does the same for `ssh-agent.exe`. ([OpenSSH install script](https://github.com/PowerShell/openssh-portable/blob/latestw_all/contrib/win32/openssh/install-sshd.ps1))
2. On this host, RedirectionGuard was active in the SSH process tree but not in `services.exe`.
3. WinGet's command aliases add a filesystem redirection step. WinGet stores each portable package under `WinGet\Packages`, creates a symbolic link under `WinGet\Links`, and puts the links directory on `PATH`. ([WinGet portable-app design](https://github.com/microsoft/winget-cli/blob/master/doc/specs/%23182%20-%20Support%20for%20installation%20of%20portable%20standalone%20apps.md))
4. Under the restricted SSH process tree, traversing a measured WinGet link failed while running the real package file succeeded. A Mise shim later reached the same failure because the native Windows shim starts `mise x -- <tool>` by resolving `mise` from `PATH`. ([Mise native shim source](https://github.com/jdx/mise/blob/main/crates/mise-shim/src/main.rs))

This is a strong explanation, not a complete proof of Windows' trust decision. Microsoft's RedirectionGuard documentation says enforcement prevents traversal of filesystem junctions created by non-admin users. It does not explain how every symbolic-link reparse point is classified. ([RedirectionGuard policy](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process-mitigation-redirection-trust-policy))

## Host measurements

These are measurements from 2026-08-21, not externally sourced claims.

- P/Invoke `GetProcessMitigationPolicy` with `ProcessRedirectionTrustPolicy = 16` returned `Flags = 1` for `sshd.exe` and its `cmd.exe` and `powershell.exe` descendants.
- The same call returned `Flags = 0` for `services.exe`.
- The WinGet `Links` entries for `mise.exe`, `fzf.exe`, and `chezmoi.exe` were symbolic-link reparse points.
- Invoking a WinGet alias failed. Invoking the real package `mise.exe` succeeded.
- A Mise shim then failed with OS error 448, `The path cannot be traversed because it contains an untrusted mount point.`

The API defines `ProcessRedirectionTrustPolicy` as the RedirectionGuard policy and returns a `PROCESS_MITIGATION_REDIRECTION_TRUST_POLICY` structure. In that structure, bit 0 is `EnforceRedirectionTrust`, so `Flags = 1` means enforcement is on. ([policy enumeration](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-process_mitigation_policy), [`GetProcessMitigationPolicy`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessmitigationpolicy), [policy structure](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process-mitigation-redirection-trust-policy)) Windows implements NTFS links with reparse points. ([reparse points](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-points))

## What the measurements establish

The `services.exe` result rules out the simple explanation that every service process had the mitigation. The OpenSSH installer targets `sshd.exe` by image name, and the live-process measurements show that the resulting SSH shell processes also had enforcement active. The measurements do not establish the exact propagation mechanism from `sshd.exe` to each shell descendant.

The alias-versus-target comparison isolates the extra WinGet link traversal as the important path difference. The error text also matches current WinGet reports where RedirectionGuard rejects canonicalization of user-scope `WinGet\Links` symlinks while the targets remain under `WinGet\Packages`. ([WinGet issue 6211](https://github.com/microsoft/winget-cli/issues/6211)) Still, this host test does not prove that all WinGet links fail or that link ownership alone determines trust.

The Mise failure is one step removed. Current Windows `exe` shims are ordinary copies of `mise-shim.exe`, not symbolic links, but that shim launches `mise` by command name. A non-reparse shim can therefore fail when its next lookup selects the WinGet `mise.exe` alias. Mise also offers `file`, `hardlink`, and `symlink` modes; only the last one is itself an NTFS symbolic link. ([Mise `windows_shim_mode`](https://mise.jdx.dev/configuration/settings.html#windows_shim_mode), [native shim source](https://github.com/jdx/mise/blob/main/crates/mise-shim/src/main.rs))

The command-palette Windows launcher currently works around this problem. It resolves real Mise executables rather than shims and runs the restricted WinGet `fzf` package through Git Bash, as recorded in [Herdr integration and plugin management](herdr-plugins.md#command-palette).

## Safe next steps

Prefer fixes that remove reparse-point traversal from the SSH execution path:

- Keep using absolute real package paths under `WinGet\Packages` in service and launcher code. Resolve the installed location during setup or refresh rather than relying on an unversioned hard-coded package directory.
- For stable tools, install or copy the executable into a normal, access-controlled directory on `PATH`. Mise documents a manual Windows installation from its release archive as an alternative to WinGet. ([Mise installation](https://mise.jdx.dev/installing-mise.html#windows-manual))
- Test Mise's non-reparse `hardlink` mode where source and shim are on the same filesystem. The default `exe` mode is also a normal copied file, but it still resolves `mise` from `PATH`, so put the real Mise package directory before `WinGet\Links` or use a wrapper that invokes the real path. ([Mise `windows_shim_mode`](https://mise.jdx.dev/configuration/settings.html#windows_shim_mode), [native shim source](https://github.com/jdx/mise/blob/main/crates/mise-shim/src/main.rs))
- Test a machine-scope or administrator-created WinGet link separately. RedirectionGuard documents creator privilege as relevant for junctions, but the result for these symbolic links must be measured rather than assumed. ([RedirectionGuard policy](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process-mitigation-redirection-trust-policy))
- Track the WinGet RedirectionGuard work and retest after Windows, OpenSSH, or WinGet updates. WinGet has a direct report and minimal reproduction for this interaction. ([WinGet issue 6211](https://github.com/microsoft/winget-cli/issues/6211))

For a tighter diagnosis, record each link's target, reparse tag, owner, ACL, and creation context; compare a local shell with the SSH shell; and run the same alias and real-target probes from a small process that explicitly enables RedirectionGuard. Also inspect the OpenSSH IFEO value and live process flags after each OpenSSH update.

Disabling RedirectionGuard should be a last resort. Enforcement exists to block traversal of redirections Windows considers untrusted, so turning it off weakens that protection. Audit mode logs suspect traversal without blocking it and is safer for a temporary compatibility study, but it is not an equivalent security setting. ([RedirectionGuard policy](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process-mitigation-redirection-trust-policy))
