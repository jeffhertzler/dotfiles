# Cross-platform divergence inventory

Snapshot date: 2026-07-27
Configuration baseline: a9ba68c on normalize/multi-platform
Machines: native Windows/Git Bash, Ubuntu WSL, macOS, EndeavourOS/Arch
Default disposition: preserve the working state until each row is reviewed.

This document records both actual target drift and deliberate or conservative
profile splits. A clean chezmoi status does not mean the machines are unified;
it only means the current policy is being followed.

Governing policy decided after the initial inventory: each application gets one
shared configuration, machines explicitly opt into the applications they use,
OS conditionals are limited to genuinely required behavior, and machine-local
values stay in unmanaged local overlays.

## Current health and drift

| ID | Machine | Config baseline | Managed target status | Notes |
|---|---|---|---|---|
| S01 | Windows | a9ba68c | Clean | Uses the Windows worktree at C:/Users/Jeff Hertzler/Documents/dotfiles. Shared LazyGit-to-Neovim, local directional splits, named-pipe-safe Herdr reordering, and the portable AgentBridge registry are active. Windows renders helper commands through Node with absolute paths because Herdr runs custom commands through cmd.exe. |
| S02 | WSL | a9ba68c | Clean | Native source clone at ~/.local/share/chezmoi. Shared LazyGit-to-Neovim, local directional splits, Herdr reordering, and the portable AgentBridge registry are active. |
| S03 | macOS | a9ba68c | Clean | Native source clone preserved with a backup branch and stash. Shared Neovim, Pi, LazyGit-to-Neovim, local directional splits, Herdr reordering, and the portable AgentBridge registry are active. |
| S04 | Arch | a9ba68c | Clean | LazyGit-to-Neovim, Herdr reordering, and the portable AgentBridge registry are shared; plugin-dependent full-layout splits remain Arch-only. |

## Installed-tool matrix

This is executable discovery, not a package-management declaration. WSL values
come from its initialized Zsh/Mise environment. Windows wt is Windows Terminal,
not Worktrunk.

| Tool group | Windows | WSL | macOS | Arch |
|---|---|---|---|---|
| Git and gh | Git and gh | Git and gh | Git and gh | Git and gh |
| Neovim and LazyGit | Both | Both | Both | Both |
| Herdr | Installed | Installed | Installed | Installed |
| OpenCode | Official installer 1.18.7 | Official installer 1.18.7 | Official installer 1.18.7 | Official installer 1.18.7 |
| Zsh | Absent | Installed | Installed | Installed |
| Starship | Not found in Git Bash PATH during inventory | Installed | Installed | Installed |
| Atuin | Installed | Installed | Installed | Installed |
| bottom | Absent | Absent | Installed | Installed |
| bat | 0.26.1 via WinGet | 0.26.1 official Debian package | 0.26.1 via Homebrew | 0.26.1 |
| LazyDocker, Posting | Absent | Absent | Installed | Installed |
| tmux, Workmux | Absent | tmux only | Both | Both |
| Worktrunk | Absent; wt means Windows Terminal | Absent | Absent | Installed |
| Yazi | Absent | Absent | Installed | Installed |
| Pi | 0.82.1 @earendil fork via Mise | 0.82.1 via Mise | 0.82.1 @earendil fork via Volta | 0.82.1 @earendil fork via Volta |
| Pi tool manager | Mise 2026.7.12 via WinGet | Mise | Volta | Volta |
| Go | Absent | Installed via Mise | Installed | Installed |

## Policy divergences to review line by line

Kinds:

- Required: the operating systems genuinely need different commands or paths.
- Conservative: isolation was chosen to avoid breaking a working machine.
- Intentional: the behavior was explicitly retained during this pass.
- Historical: inherited configuration that has not yet been re-decided.

| ID | Area | Current behavior | Kind | Question for review |
|---|---|---|---|---|
| D01 | Overall ownership | Each application has one shared configuration. Every machine explicitly enables the applications it uses; only required OS behavior is conditional, and machine-local values use unmanaged overlays. The current implementation still needs to be migrated toward this policy one application at a time. | Decided | Adopted as the governing policy. |
| D02 | Generic Linux | There is no current generic native-Linux machine. The minimal profile remains only as a safe fallback and carries no support or unification promise. | Decided | Revisit only when a real non-Arch, non-WSL Linux machine is added. |
| D03 | Source topology | Each machine keeps a native Chezmoi clone tracking the published origin/normalize/multi-platform branch. No machine is the permanent authoritative source; Windows is only the current editing location. Local bundles are retired in favor of ordinary upstream push and fast-forward pull/fetch. The branch can be merged into master after this review. | Decided and implemented | Continue with the tracked branch; merge it into master only after the divergence review is complete. |
| D04 | Windows shell | Git Bash is the default for native Windows workflows and local Herdr. WSL remains a fully supported parallel shell/environment for Linux workflows; the two are not mutually exclusive. Windows manages Git Bash startup while WSL manages its own Zsh startup. | Decided | Keep both available. |
| D05 | Unix shells | WSL, Mac, and Arch render one shared Zsh baseline. Optional portable integrations are capability-guarded; the shared template selects one profile overlay, while explicitly platform-owned behavior lives in that overlay. Rendered syntax, isolated startup, real login-shell startup, and narrow Chezmoi verification passed on all three machines. | Decided and implemented | Keep unified; add platform branches only for demonstrated incompatibilities. |
| D06 | Zsh environment | WSL, Mac, and Arch render one shared .zshenv with a static ordered list of expected home tool directories, including ~/.atuin/bin, ~/.opencode/bin, and the future Mise shim location. PATH is deduplicated. Git Bash adds ~/.opencode/bin in its own .bashrc and receives Atuin from the native WinGet links directory rather than common.sh. Windows adds the native Mise shim directory through its user PATH for Pi. Broader Mise adoption remains deferred. | Decided and implemented | Keep unified; broader Mise adoption remains deferred. |
| D07 | Zsh plugins | WSL, Mac, and Arch share the same Antidote plugin list and ez-compinit loads first. | Intentional | Keep unified. |
| D08 | Shell aliases | common.sh supplies editor, Herdr, LazyGit, Chezmoi, Git, updater, and portable tool helpers to Bash and Zsh. Optional tools are capability-guarded; shell initialization and edit/reload aliases remain shell-specific, while Arch retains tmux, Workmux, and Tailscale aliases in .arch.zsh. Login-shell and full Chezmoi verification passed on all four machines. | Decided and implemented | Keep portable interactive behavior in common.sh; keep shell initialization and platform ownership outside it. |
| D09 | Shell overlays | WSL sources .wsl.zsh, Mac sources .mac.zsh, and Arch sources .arch.zsh. | Required/intentional | Review each overlay and move only truly shared functions upward. |
| D10 | Project overlays | Greenlight and Vimme live under ~/.config/shell and are managed on WSL, Mac, and Arch. Each exits without side effects unless its ~/dev checkout exists. OpenCode's portable ocp/ocw helper now lives at ~/.config/shell/opencode.sh on all four machines; obsolete .ocprofile.zsh files were moved into local backups. | Decided and implemented | Keep checkout-specific behavior guarded and portable shell helpers under XDG config. |
| D11 | Opt-in secrets | Every profile ignores .private.zsh plus the .ssh/id_rsa key pair unless CHEZMOI_INCLUDE_SECRETS=1. The redundant Windows/WSL/macOS platform ignores were removed so the explicit environment opt-in has the same meaning everywhere. 1Password CLI is available on all four systems; no secret was fetched during convergence. | Decided and implemented | Keep secrets and their paired public material excluded by default and require the explicit per-command environment opt-in. |
| D12 | XDG root | Managed app configs use ~/.config. Windows sets XDG_CONFIG_HOME in Git Bash and as a user environment variable for Neovim. | Intentional | Keep. Existing long-lived Windows processes may need restart to see the environment variable. |
| D13 | Git common core | Name, email, default branch, pull behavior, excludes file, and ~/.config/git/local.config include are shared. WSL and Arch keep their gh credential-helper commands in that unmanaged local overlay rather than the shared file; no credential is stored in Chezmoi. opencode.json is not globally ignored; any local-only project config must use that repository's .git/info/exclude. The one discovered project opencode.json is intentionally tracked, so it needs no private exclusion. | Intentional | Keep global ignores limited to universally disposable state and machine-specific authentication plumbing in local.config. |
| D14 | Git credentials | Unmanaged ~/.config/git/local.config files explicitly retain HTTPS fallback: Windows resets to Git Credential Manager, macOS resets to Keychain, and WSL and Arch use URL-scoped gh helpers for GitHub and Gist. | Decided and implemented | Keep legacy HTTPS repositories working while all authentication plumbing remains outside Chezmoi. |
| D15 | Git LFS | Windows, WSL, Mac, and Arch render the same Git LFS filters. WSL was added after confirming the executable and filter behavior. | Decided and implemented | Keep the filters unified while Git LFS remains installed on every supported profile. |
| D16 | Greenlight Git include | The checkout-specific ~/dev/greenlight include was removed from the shared template. Mac and Arch retain it in their unmanaged ~/.config/git/local.config files, which the shared Git config already includes. Chezmoi does not own or copy the project-owned ~/dev/greenlight/.gitconfig. | Decided and implemented | Keep checkout-specific includes in the unmanaged local overlay. |
| D17 | lockb Git diff | The stale Mac-only Bun lockb textconv was removed. No bun.lockb files were found under Windows Documents or Mac ~/dev. | Decided and implemented | Restore only if a real binary Bun lockfile needs text conversion again. |
| D18 | Delta | Delta config and Catppuccin include were removed because Delta was not active. | Intentional during this pass | Reconsider only if Delta is deliberately adopted again. |
| D19 | Machine Git data | Arch stores its CodeRabbit machine ID and Pop!_OS mount include in unmanaged ~/.config/git/local.config, mode 0600. | Intentional | Keep machine IDs and machine paths out of the public source. |
| D20 | LazyGit | All four profiles use one LazyGit template and the same custom lazygit-nvim behavior. Unix renders direct helper commands; native Windows renders the same commands through Git Bash because LazyGit launches them through cmd.exe. The current edit-return implementation passed interactively on Windows, WSL, and Arch; macOS uses the same Unix RPC path as Arch and was accepted without a redundant interactive test. | Decided, structurally unified, and implemented | Keep one template with only the required Windows launcher string conditionalized. |
| D21 | GitHub CLI config | GitHub CLI is installed and logged in on all four machines. All four manage only ~/.config/gh/config.yml at mode 0600 with SSH as the preferred Git protocol; account records and tokens remain unmanaged in hosts.yml or the native keyring. Windows was verified directly, and the user verified macOS interactively because its Keychain-backed session is not visible through remote SSH automation. | Decided and implemented | Prefer SSH for new GitHub operations while retaining machine-local HTTPS helpers for legacy remotes. |
| D22 | SSH config | ~/.ssh/config and known_hosts remain completely unmanaged. GitHub's published Ed25519 host fingerprint was verified before github.com was accepted locally on each machine. | Explicit prior decision | Keep SSH host policy machine-local. |
| D23 | SSH keys | Windows, WSL, macOS, and Arch intentionally store the same RSA private key locally; its public key is registered with GitHub and SSH authentication passed on all four systems. Chezmoi retains the matching 1Password-backed template as an optional recovery/bootstrap path when CHEZMOI_INCLUDE_SECRETS=1. Direct machine-to-machine recovery remains acceptable. | Decided and implemented | Keep raw local storage and the explicit 1Password recovery option; do not manage SSH config or known_hosts. |
| D24 | Starship | The same ~/.config/starship.toml is managed on all supported profiles. | Intentional | Keep. |
| D25 | Herdr core | The same core UI, theme, history, and navigation keys are managed on Windows, WSL, Mac, and Arch. | Intentional | Keep. |
| D26 | Herdr Windows terminal | Windows alone sets Git Bash as Herdr's shell, new_cwd=follow, and the preview update channel. Native Windows releases are currently preview-only and Herdr rejects the stable channel there. | Required/intentional | Keep until Herdr publishes stable native Windows releases. |
| D27 | Herdr advanced commands | Local left/up directional splits, tab/workspace reordering, and the Bash/fzf popup launcher are shared by Windows, WSL, Mac, and Arch. Reordering uses a per-user runtime/temp lock keyed to the Herdr socket, including native Windows named pipes. The low-value session picker and its `hs` alias were retired. Arch alone retains plugin-dependent full-layout splits, Worktrunk actions, and the popup's legacy Workmux entry. | Decided and implemented | Keep the portable behavior shared and the plugin/legacy additions Arch-only. |
| D28 | Herdr plugin subtree | Herdr plugin actions and plugin configuration are Arch-only. The installed plugins are user-shared under ~/.config/herdr/plugins and remain outside Chezmoi ownership. | Conservative | Decide whether Mac should share the plugin set. |
| D29 | Herdr plugin installer | The obsolete session-by-session plugin bootstrap was removed. The former `R` status meant Chezmoi would run the run-after script; it did not indicate an old target file. Arch already has the four plugins installed in shared user scope. | Decided and implemented | Keep plugin installation outside Chezmoi unless a new shared-user bootstrap is deliberately designed. |
| D30 | Tunnel command | WSL uses systemd user services with tailscale/lan routes. Mac uses SSH ControlMaster sockets with tailscale/lan/remote routes. Windows and Arch do not receive tunnel. | Required | Keep separate implementations behind one command name. |
| D31 | Neovim ownership | Windows, WSL, Mac, and Arch manage the shared LazyVim tree. Mac's former 31-file independent tree was backed up and fully replaced; the shared 111-file source tree, all 80 configured Lazy plugins, and normal headless startup were verified. lazy-lock.json remains unmanaged runtime state. | Decided and implemented | Keep all four machines on the shared tree. |
| D32 | Neovim platform guards | Windows uses LLVM, Git Bash shell settings, Node-launched Oxfmt, and a Windows markdown-preview installer. Unix uses Volta when present. FGA, tmux, Yazi, and Go integrations have executable/file guards. | Required/intentional | Keep guards; review whether any can simplify after ownership converges. |
| D33 | Neovim language support | TypeScript and Python were user-verified on Windows/WSL. On Mac, tsgo, Pyright, Ruff, and Oxfmt were verified inside Neovim after plugin synchronization. Go tooling is skipped only when no Go executable is visible. | Intentional | Keep executable guards and repeat interactive project verification only if a Mac-specific problem appears. |
| D34 | Neovim lockfile | lazy-lock.json was removed from source and excluded through .chezmoiignore. Each live Neovim installation retains its local lockfile as unmanaged runtime state. | Decided and implemented | Do not place Lazy's per-machine lockfile in Chezmoi source or managed state. |
| D35 | OpenCode ownership | Windows, WSL, Mac, and Arch manage one fixed ~/.config/opencode/opencode.json plus the shared ocp/ocw shell helper. Sharing is disabled in the fixed config. Credentials remain outside Chezmoi. | Decided and implemented | Keep the portable config shared and credentials unmanaged. |
| D36 | OpenCode account profiles | Every machine has unmanaged personal and work auth files under ~/.local/share/opencode/profiles. Both profiles were copied from the established Arch files and verified byte-for-byte across all four machines. ocp/ocw atomically replace ~/.local/share/opencode/auth.json with a relative symlink before launch; concurrent personal/work OpenCode processes are intentionally unsupported. Windows, WSL, and Arch were left active on personal; Mac was left active on work. | Decided and implemented | Keep the simple single-active-profile model unless concurrent account use becomes important again. |
| D37 | OpenCode installation | All four machines use OpenCode's official installer with --no-modify-path and were verified at 1.18.7. Chezmoi owns shell PATH setup. WSL's former Mise package and config entry were removed only after the official binary passed. | Decided and implemented | Use the official installer for future OpenCode updates; broader Mise adoption remains a separate deferred topic. |
| D38 | Workmux ownership | Workmux is preserved as Arch-only legacy configuration. Mac still has the Workmux executable installed, but its ~/.config/workmux directory was removed, its shell completion is no longer loaded, and the shared Herdr popup hides its Workmux entry outside Arch. WSL does not have Workmux. | Explicit user decision | Keep the Arch source until eventual retirement. |
| D39 | Workmux command | Preserved Arch source config now matches the known-working live command `opencode`. The redundant `--port` flag defaults to 0 when used. | Decided and implemented | Keep the legacy config aligned with the live command until Workmux is retired. |
| D40 | Worktrunk | Worktrunk config, Herdr actions, and seeding helper are Arch-only; Mac and WSL lack Worktrunk. | Conservative | Install and share, or keep Arch-only? |
| D41 | tmux | tmux is preserved as Arch-only legacy configuration. Mac and WSL still have tmux installed. Mac's ~/.config/tmux directory, including downloaded TPM plugin clones, was removed; WSL's independent state remains untouched. | Explicit user decision | Keep the Arch source until eventual retirement. |
| D42 | Yazi | Mac and Arch manage Yazi. WSL and Windows ignore it. Mac renders open; Linux renders xdg-open. | Required plus conservative | Keep opener split; decide whether to install/share Yazi on WSL. |
| D43 | Atuin | Windows, WSL, Mac, and Arch manage the same Atuin config and shell integration. Windows uses WinGet with Bash/ble.sh integration, WSL uses Atuin's binary-only release installer, Mac uses Homebrew, and Arch uses pacman. Git Bash reapplies Atuin's vi-insert Ctrl-R binding through ble.sh's post-import callback because ble.sh's fzf integration loads later in idle time and otherwise replaces it; vi-normal Ctrl-R is explicitly restored to redo, matching Arch Zsh. History databases remain machine-local, no machine is logged into remote sync, and the shared config explicitly sets auto_sync=false. | Decided and implemented | Keep Atuin local-only unless remote sync is deliberately adopted later. |
| D44 | bat and bottom | Windows, WSL, Mac, and Arch run Bat 0.26.1 with the same managed config and bundled Catppuccin Mocha theme. WSL uses Bat's official Debian package because Ubuntu's older package lacked the shared bundled theme. Native Windows uses BAT_CONFIG_PATH to keep Bat on the shared XDG path. The inert Bottom config remains retired. | Decided and implemented | Keep Bat unified; Bottom no longer has managed configuration. |
| D45 | LazyDocker and Posting | Mac and Arch manage both tools. WSL and Windows ignore them. | Explicit user decision | Keep both tools fully managed on Mac and Arch only. |
| D46 | Pi ownership | Windows, WSL, Mac, and Arch share the human-authored Pi settings, profiles, keybindings, renderer, and portable extensions. auth.json, caches, logs, trust, model/session runtime state, and generated integrations remain unmanaged. | Decided and implemented | Keep the shared portable configuration enabled on all four machines. |
| D47 | Pi machine-local state | Arch's auth profiles were copied byte-for-byte to WSL, Mac, and Windows outside Chezmoi. Unix copies use mode 0600; Windows inherits only SYSTEM, Administrators, and the user with full control. herdr-agent-state.ts remains Herdr-managed; Arch's moshi-hooks.ts remains generated and local; workmux-status.ts remains only on legacy Arch and was retired from Mac into the Pi backup. | Explicit user decision | Keep generated integrations and credentials outside Chezmoi. |
| D48 | Agent skills | .agents is Arch-only. Mac has agent/cursor-agent executables but no ~/.agents directory; WSL and Windows ignore it. | Conservative | Share agent-review skill/config where the clients support it? |
| D49 | Local helper scripts | lazygit-nvim and herdr-popup-picker are shared by Windows, WSL, Mac, and Arch. The popup retains its Bash/fzf UI, checks extension subcommands such as `gh dash` rather than only their host executable, and enables Workmux only from the Arch binding. tunnel remains profile-specific on WSL/Mac. tmux helpers and worktrunk-seed remain Arch-only legacy. The low-value herdr-session-picker was retired; agent-review remains under review. | Partially decided and implemented | Review agent-review with D48 next. |
| D50 | macOS allowlist | Mac manages Git, gh config, LazyGit, Herdr core/reordering/popup and its helper, Neovim, OpenCode, Pi, Starship/common shell, Greenlight/Vimme shell helpers, Atuin, bat, LazyDocker, Posting, Yazi, tunnel, and lazygit-nvim. It intentionally no longer manages legacy tmux/Workmux or inert Bottom configuration. It still ignores agents, SSH, and the remaining local helpers. | Conservative choices plus explicit legacy, Pi, Atuin, and Herdr decisions | This remains the main list to reconsider if greater unification is desired. |
| D51 | WSL allowlist | WSL manages Git, gh config, Atuin, Bat, LazyGit and its Neovim bridge, Herdr core/reordering/popup and its helper, Neovim, OpenCode, Pi, Starship/common shell, Zsh plugins, tunnel, and the checkout-guarded Greenlight/Vimme shell helpers. It ignores the remaining workstation tools; the project helpers are present but inert because their ~/dev checkouts are absent. | Conservative choices plus explicit Atuin, Bat, Pi, LazyGit, and Herdr decisions | Decide which remaining Mac/Arch tools should join the WSL baseline. |
| D52 | Windows allowlist | Windows manages Git, gh config, Atuin, Bat, LazyGit and its Git-Bash-launched Neovim bridge, Herdr core/reordering/popup and its helper, Neovim, OpenCode, Pi, Starship/common shell, and Git Bash startup. Atuin uses the existing ble.sh line editor for accurate Bash history hooks. The popup helper is launched through Git Bash's space-free Windows path because Herdr runs native custom commands through cmd.exe. | Conservative plus explicit Atuin, Bat, gh, Pi, LazyGit, and Herdr decisions | Decide whether to install/share other native tools. |
| D53 | Nushell | A three-line 2021 TOML-era Nushell config was removed; Nushell was absent and modern Nushell no longer uses that format. | Intentional | Restore only if adopting modern Nushell with a new config. |
| D54 | Source documentation | docs is ignored by chezmoi so this inventory is not deployed into any home directory. | Intentional | Keep repository documentation outside target state. |
| D55 | Legacy shell integration | Mac no longer loads tmux/Workmux aliases or Workmux completion. Arch retains them in .arch.zsh rather than the shared template. The Mac tmux and Workmux config directories were removed after the user confirmed they were unnecessary. | Explicit user decision | Preserve only the Arch legacy setup until eventual retirement. |
| D56 | Pi tool manager | Windows and WSL use Mise for Pi; Mac and Arch use Volta. Native Windows Mise is intentionally limited to Pi and its config remains unmanaged. Volta upstream is now unmaintained and recommends migrating to Mise. | Explicitly deferred | Revisit broader Mise adoption and any Volta migration as a separate compatibility review. |
| D57 | LazyGit editor bridge | All four profiles use the custom lazygit-nvim bridge rather than LazyGit's built-in nvim preset. Unix invokes it directly. Native Windows LazyGit runs editor commands through cmd.exe, so its rendered config launches the same script explicitly through Git Bash. All bridge RPC clients run headlessly, avoiding terminal negotiation and control-sequence output. After an in-Neovim edit it attempts a deferred `q` at 100 ms and retains the proven 250 ms attempt as a no-op fallback, allowing a normal status-0 terminal exit instead of killing the terminal buffer. The complete in-Neovim path passed interactively on Windows, WSL, and Arch; the separate Herdr-popup return passed on Arch and became substantially faster after its RPC clients were made headless. LazyVim's `<leader>gG` LazyGit binding remains available alongside Neogit on `<leader>gg`. | Corrected, optimized, and interactively verified | Keep the behavior shared; retain only the required Windows launcher syntax, guarded in-Neovim terminal return, and Herdr/tmux popup return branches. |
| D58 | Herdr reorder Windows socket | The first shared rollout passed syntax/config checks but the live Windows binding failed because Node received Herdr's bare pipe name and passed it directly to net.connect. Herdr's own bundled Node integrations prepend the Windows named-pipe namespace, so herdr-reorder now does the same. A disposable named-pipe server verified the complete request/response path before redeployment. | Corrected and implemented | Keep the platform-specific endpoint conversion inside the otherwise shared helper. |
| D59 | Herdr custom-command shell on Windows | The named-pipe-safe helper worked when invoked directly, but the binding still did not launch because Herdr executes Windows custom commands through cmd.exe and cmd.exe cannot resolve a Unix shebang path beginning with `~`. Windows now renders `node "C:/Users/Jeff Hertzler/.local/bin/..."`; Unix keeps the direct `~/.local/bin/...` command. The exact rendered cmd.exe command and the live prefix binding both moved the focused tab successfully. | Corrected and implemented | Keep one shared behavior with only the launcher syntax conditionalized for Windows. |
| D60 | AgentBridge registry portability | AgentBridge's fallback used Vim's unavailable `getuid()` function, allowed `:` from Herdr pane IDs in filenames, and assumed Unix sockets when LazyGit validated a published server. Windows now publishes under its temp directory, Unix uses XDG_RUNTIME_DIR or libuv's user id, pane IDs use a portable filename, and consumers validate servers through Neovim RPC so native Windows named pipes work. Native Windows/Git Bash and both Unix registry branches passed publish/read/connect/remove integration tests; the AgentReview suite also passed. | Corrected and implemented | Keep one registry convention with only the runtime-root selection conditionalized by platform. |

### D49 helper classification

| Helper | Classification | Current decision |
|---|---|---|
| lazygit-nvim | Cross-platform bridge from LazyGit back to the originating Neovim instance | Managed on all four machines. Unix invokes it directly; Windows invokes the same script through Git Bash. |
| tunnel | Shared command with required profile-specific implementations | Managed only on WSL and Mac. |
| tmux-lazygit-popup, tmux-nvim-server, tmux-preview-update, tmux-yazi-split | Legacy tmux integration | Managed only on Arch. Four matching but unmanaged Mac leftovers were retired into the dated helper backup. |
| worktrunk-seed | Worktrunk-specific | Managed only on Arch with the legacy Worktrunk setup. |
| herdr-directional-split.mjs | Portable Herdr behavior with an optional plugin-dependent mode | Managed on all four machines. Local left/up commands are shared; full-layout commands stay Arch-only with edi.layout-tools. |
| herdr-reorder.mjs | Portable Herdr tab and workspace/worktree-group reordering | Managed on all four machines with shared prefix+ctrl+h/l/k/j bindings. Its lock lives under XDG_RUNTIME_DIR or the OS temp directory and is keyed to the socket path. |
| herdr-popup-picker | Portable Herdr command launcher with optional tools | Managed on all four machines at prefix+p. It retains the Bash/fzf UI; macOS uses Homebrew Bash because the system Bash is too old, native Windows launches it through Git Bash, and only Arch enables the legacy Workmux item. |
| herdr-session-picker | Low-value fuzzy session attachment helper | Retired from source and live Arch state together with its shared `hs` alias. |
| agent-review | Shared Neovim feature with a currently Unix/GNU-specific Bash client | Defer to D48. A cross-platform implementation should avoid Bash 4, jq, and GNU base64 requirements. |

## Deferred actual changes

None. Windows, WSL, Mac, and Arch currently have no managed target drift.
The live Neovim lazy-lock.json files remain present but are intentionally
unmanaged and ignored by Chezmoi.

Mac Pi startup currently emits npm's deprecation warning for an existing
private-registry `always-auth` setting. Pi still starts successfully; review the
work npm configuration separately rather than changing it as part of Pi setup.

## Rollback points

### Repository-level

- Windows branch: normalize/multi-platform.
- Mac backup branch: backup/mac-pre-normalization-20260727-034132.
- Mac stash: mac pre-normalization 20260727-034132.
- Arch backup branch: backup/arch-pre-normalization-20260727-034755.
- Arch stash: arch pre-normalization 20260727-034755.
- Arch also has an older unrelated stash named asdf; do not alter it casually.
- OpenCode migration backups: %LOCALAPPDATA%/dotfiles-backups/20260727-2139-opencode-9d2dacb on Windows and ~/.local/state/dotfiles-backups/20260727-2139-opencode-9d2dacb on WSL, Mac, and Arch.
- Mac pre-shared Neovim backup: ~/.local/state/dotfiles-backups/20260727-2205-mac-nvim-pre-shared. Both the verified copy and the retired live tree are retained there.
- Pi convergence backups: ~/.local/state/dotfiles-backups/20260727-2235-pi-convergence on WSL, Mac, and Arch. Mac's retired Workmux extension is additionally under retired-live/.pi/agent/extensions in that backup.
- Mac Pi changed from Homebrew 0.80.6 plus the original Volta package 0.70.6 to only @earendil-works/pi-coding-agent 0.82.1 via Volta. Homebrew also removed ten dependencies it classified as unused; all removed formulae are reinstallable through Homebrew if another workflow needs them.

### Windows

- C:/Users/Jeff Hertzler/.gitconfig.pre-xdg-20260727-032541
- D08 shared-shell backup:
  C:/Users/Jeff Hertzler/.config/shell/common.sh.pre-chezmoi-20260727-170115
- Legacy Neovim rollback remains under LocalAppData from the Windows migration.
- Windows had no pre-existing ~/.pi tree. Pi 0.82.1 is installed as the pinned npm:@earendil-works/pi-coding-agent tool in unmanaged ~/.config/mise/config.toml; Mise 2026.7.12 is WinGet package jdx.mise. The only PATH addition is %LOCALAPPDATA%/mise/shims in the user PATH. Auth remains recoverable from the matching Unix copies and the dated Pi convergence backups.
- Herdr directional-sharing config backup: %LOCALAPPDATA%/dotfiles-backups/20260727-herdr-directional-sharing/config.toml.
- LazyGit bridge backup: %LOCALAPPDATA%/dotfiles-backups/20260727-lazygit-bridge/config.yml.
- Herdr reordering backup: %LOCALAPPDATA%/dotfiles-backups/20260727-herdr-reorder/config.toml.
- Herdr reordering pipe-fix backup: %LOCALAPPDATA%/dotfiles-backups/20260727-herdr-reorder-pipe-fix/herdr-reorder.mjs.
- Herdr Windows command-shell backup: %LOCALAPPDATA%/dotfiles-backups/20260727-herdr-windows-command-shell/config.toml.
- AgentBridge Windows registry backup: %LOCALAPPDATA%/dotfiles-backups/20260727-agentbridge-windows-registry contains the prior server.lua and lazygit-nvim targets.
- Session-picker retirement backup: %LOCALAPPDATA%/dotfiles-backups/20260727-retire-herdr-session-picker/common.sh.
- Bat/gh convergence registry backup: %LOCALAPPDATA%/dotfiles-backups/20260727-bat-gh-convergence/HKCU-Environment-before.reg. BAT_CONFIG_PATH was previously unset; remove that user variable to roll back the Windows Bat path override.
- Git transport-policy backup: %LOCALAPPDATA%/dotfiles-backups/20260727-git-transport-policy records that the unmanaged Git local overlay did not previously exist and retains the former dotfiles repository config.
- 1Password CLI 2.34.1 was installed through WinGet package AgileBits.1Password.CLI; `winget uninstall --id AgileBits.1Password.CLI --exact` removes it.
- Atuin 18.18.0 was installed through WinGet package Atuinsh.Atuin; `winget uninstall --id Atuinsh.Atuin --exact` removes the binary without touching its local history database.
- The formatting-only config.yml rewrite made by Windows `gh auth login` is backed up under %LOCALAPPDATA%/dotfiles-backups/20260727-gh-login-rewrite; the managed config was restored without affecting keyring authentication.

### WSL

- ~/.gitconfig.pre-xdg-20260727-072602
- ~/.zshrc.local.pre-chezmoi-20260727-072602
- ~/.config/herdr/config.toml.pre-chezmoi-20260727-073034
- ~/.config/gh/config.yml.pre-chezmoi-20260727-073554
- ~/.zsh_plugins.txt.pre-chezmoi-20260727-074721
- D05 unified-shell backups: ~/.zshrc.pre-chezmoi-20260727-175006 and
  ~/.wsl.zsh.pre-chezmoi-20260727-175006.
- D06 shared-environment backup: ~/.zshenv.pre-chezmoi-20260727-203355.
- D06 static-PATH backup: ~/.zshenv.pre-chezmoi-20260727-204605.
- D08 shared-shell backups use timestamp 20260727-210115 for common.sh and
  ~/.zshrc.
- Previous Neovim tree: ~/.config/nvim.pre-chezmoi-20260727-070409
- GitHub credential-helper backup: ~/.local/state/dotfiles-backups/20260727-github-credential-helper/config. The local.config overlay did not previously exist; it was created to hold gh's helper command outside managed state.
- Git transport-policy backup: ~/.local/state/dotfiles-backups/20260727-git-transport-policy retains local.config, the former dotfiles repository config, and the prior gh hosts.yml.
- 1Password CLI 2.35.0 was installed from 1Password's official standalone Debian package without adding an apt repository; `sudo apt remove 1password-cli` removes it.
- Atuin 18.18.1 was installed with Atuin's binary-only release installer under ~/.atuin/bin with PATH modification disabled. Removing ~/.atuin removes that installation; ~/.local/share/atuin remains the separate local history database.

### macOS

- Config backups use timestamp 20260727-034417 for Git, gh, and Yazi.
- Shell/plugin backups use timestamps 20260727-034722 and 20260727-034734.
- Latest Mac Zsh legacy-gating backup uses timestamp 20260727-131806.
- D05 unified-shell backup: ~/.zshrc.pre-chezmoi-20260727-135007.
- D06 shared-environment backup: ~/.zshenv.pre-chezmoi-20260727-163356.
- D06 static-PATH backup: ~/.zshenv.pre-chezmoi-20260727-164606.
- D08 shared-shell backups use timestamp 20260727-170116 for common.sh and
  ~/.zshrc.
- D10 Greenlight/Vimme XDG migration backups:
  - WSL: ~/.local/state/chezmoi-backups/project-overlays-20260727-211130
  - Mac: ~/.local/state/chezmoi-backups/project-overlays-20260727-171131
  - Arch: ~/.local/state/chezmoi-backups/project-overlays-20260727-171132
- Greenlight no-TERM follow-up backups use timestamps 20260727-211236 on WSL,
  20260727-171237 on Mac, and 20260727-171238 on Arch under
  ~/.local/state/chezmoi-backups/greenlight-tput-*.
- Earlier inline backup filenames are the original path plus
  .pre-chezmoi-TIMESTAMP; the D10 backup directories above retain named copies.
- Git transport-policy backup: ~/.local/state/dotfiles-backups/20260727-git-transport-policy retains local.config, the former dotfiles repository config, and the prior gh hosts.yml.
- Mac ~/.config/tmux and ~/.config/workmux were deleted directly, not moved to
  Trash. Their configuration remains in the Arch-only source; TPM plugins can
  be reinstalled but the deleted plugin clones are not directly recoverable.
- Mac helper convergence backup: ~/.local/state/dotfiles-backups/20260727-1854-helper-convergence/mac-local-bin. It contains the stale pre-shared lazygit-nvim plus copies and retired-live originals of the four removed tmux helpers.
- Herdr directional-sharing config backup: ~/.local/state/dotfiles-backups/20260727-herdr-directional-sharing/config.toml on WSL, Mac, and Arch.
- LazyGit bridge backups: ~/.local/state/dotfiles-backups/20260727-lazygit-bridge on WSL, Mac, and Arch. Mac and Arch contain direct pre-apply copies. WSL's initial backup command lost a shell variable at the PowerShell boundary, so its old config was restored from the identical Windows pre-change copy and its old helper was reconstructed byte-for-byte from commit 4725ea7 (blob 8fd9388) before verification.
- Herdr reordering backups: ~/.local/state/dotfiles-backups/20260727-herdr-reorder on WSL, Mac, and Arch. Each contains the prior config; Arch also retains its prior helper.
- Herdr reordering pipe-fix backups: ~/.local/state/dotfiles-backups/20260727-herdr-reorder-pipe-fix/herdr-reorder.mjs on WSL, Mac, and Arch.
- Herdr command-shell backups: ~/.local/state/dotfiles-backups/20260727-herdr-command-shell/config.toml on WSL, Mac, and Arch.
- AgentBridge registry backups: ~/.local/state/dotfiles-backups/20260727-agentbridge-registry on WSL, Mac, and Arch; each contains only the managed targets changed on that profile.
- Session-picker retirement backups: ~/.local/state/dotfiles-backups/20260727-retire-herdr-session-picker on WSL, Mac, and Arch; Arch also retains the retired helper itself. WSL was applied through its existing user context after transient interop launch failures cleared, without terminating the distribution.
- Simple-cleanup backups: ~/.local/state/dotfiles-backups/20260727-simple-cleanups contains the prior Git config and common.sh on WSL; the prior managed Git and Bottom configs plus a marker that Mac's Git local overlay did not exist; and the prior managed Git and Bottom configs plus unmanaged Git local overlay on Arch. WSL also gained Ubuntu's git-lfs 3.7.1 package.
- Bat/gh convergence installed Bat 0.26.1 through WinGet on Windows, Bat's official Debian package on WSL, and Homebrew on Mac; Arch already had the same Bat release. GitHub CLI 2.96.0 was installed through WinGet on Windows. Windows and WSL had no prior Bat target, and Windows had no prior gh target.

### Arch

- Git/gh/plugin backups use timestamp 20260727-034910.
- Zsh backup: ~/.zshrc.pre-chezmoi-20260727-034928.
- Neovim runtime backups use timestamp 20260727-035113.
- Pi settings backup uses timestamp 20260727-035234.
- Latest Arch Zsh legacy-gating backup uses timestamp 20260727-131806.
- D05 unified-shell backup: ~/.zshrc.pre-chezmoi-20260727-135007.
- Arch-overlay ownership backups: ~/.zshrc.pre-chezmoi-20260727-140456 and
  ~/.arch.zsh.pre-chezmoi-20260727-140456.
- D06 shared-environment backup: ~/.zshenv.pre-chezmoi-20260727-163356.
- D06 static-PATH backup: ~/.zshenv.pre-chezmoi-20260727-164606.
- D08 shared-shell backups use timestamp 20260727-170116 for common.sh and
  ~/.zshrc.
- Git transport-policy backup: ~/.local/state/dotfiles-backups/20260727-git-transport-policy retains local.config, the former dotfiles repository config, and the prior gh hosts.yml. The earlier Arch-only helper move is also backed up under 20260727-arch-gh-helper-local.

## Review order

1. D01 is decided: use shared application configs with explicit per-machine enablement.
2. D46 is complete. D49 has resolved LazyGit, tunnel, tmux, Worktrunk, local directional-split, Herdr-reordering, the popup helper, and retirement of the session picker; next review agent-review with D48. Continue D50 through D52 for remaining applications; D56 keeps broader Mise adoption deferred.
3. D05, D06, D08, and D10 are complete. Leave legacy tmux/Workmux preserved on Arch.
4. D27, D28, and D40: consolidate Herdr and Worktrunk behavior.
5. D14 through D23: finish Git, gh, SSH, and secret policy.

## Branch changes made during this pass

These commits are intentionally small so individual choices can be reverted or
rewritten during review:

- d6b9bdf add safe multi-platform profile scaffold
- 8bde75f enable shared starship config for wsl and windows
- 6c7825e normalize shared shell behavior across bash and zsh
- 2e736d7 use profile-style name for wsl zsh helpers
- 113641c align zsh overlays with machine profiles
- 8517caa split git config by machine profile
- bdf7a12 standardize lazygit on xdg config
- f6aa277 remove inactive delta configuration
- 91983bb pi feedback
- c458824 make neovim config portable
- afc4305 manage neovim on windows and wsl
- ebe0df7 skip go tooling without go
- 0c19f26 record chezmoi source directory
- a238cef disable chezmoi pager on windows
- 752bc13 share portable herdr configuration
- eb37f7d limit herdr management to core config
- 44f8486 manage opencode on wsl
- 78f5eb3 manage GitHub CLI config on WSL
- d9d66c3 keep GitHub CLI config private
- d1f21fa remove obsolete Nushell config
- 1df33c3 manage profile-specific tunnel helpers
- a05d8ce preserve tunnel script shebang
- 2c6f56d add a reviewed macOS allowlist
- 9c0ad19 avoid duplicate Unix shell initialization
- 0bf64c7 load completion support before dependent plugins
- 591f240 detect Arch-derived Linux distributions
- 652f0b7 preserve detached Herdr popup environment
- 3c15c10 select OpenCode profile by machine
- 3f0b3b8 record current Arch Pi packages
- a687299 preserve spacing in staged Pi feedback
- be2f612 keep tmux and workmux as Arch-only legacy
- 55b4235 use pi tui utils instead of custom solution to avoid issues with emojis
- 6efb058 merge Arch Pi renderer lineage
- fad0451 unify Zsh startup across Unix profiles
- b945323 move Arch shell behavior into its overlay
- 9917939 unify guarded Unix shell environment
- 6f62f52 simplify shared Unix PATH setup
- 3df506f record static shared Unix PATH policy
- 1ca3c35 resolve deferred Arch configuration drift
- 0fe25d5 ignore Neovim lockfile at Chezmoi layer
- 97fdf24 share portable shell helpers with Git Bash
- d82673f move project shell helpers under XDG config
- 4914cf6 avoid tput warnings without a terminal
- d48b617 record XDG project overlay decision
- 31ecf42 simplify opencode account profiles
- 9d2dacb scope opencode config ignores per project
- 3e1a6f9 scope opencode path to git bash
- 38a530a inline shared zsh templates
- 10ecd01 manage neovim on macos
- 7e8c212 manage pi config on wsl and macos
- d4cf9b1 manage pi config on windows
- 6084cc4 share lazygit nvim helper on unix clients
- 28d6321 share herdr directional split commands
