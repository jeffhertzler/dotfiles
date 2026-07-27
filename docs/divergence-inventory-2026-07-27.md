# Cross-platform divergence inventory

Snapshot date: 2026-07-27
Configuration baseline: 6efb058 on normalize/multi-platform
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

| ID | Machine | Current source | Managed target status | Notes |
|---|---|---|---|---|
| S01 | Windows | a687299 | Clean | Uses the Windows worktree at C:/Users/Jeff Hertzler/Documents/dotfiles. |
| S02 | WSL | a687299 | Clean when directories are excluded | Native source clone at ~/.local/share/chezmoi. ~/.config is mode 750 and ~/.config/herdr is mode 700, intentionally tighter than source-directory defaults. |
| S03 | macOS | a687299 | Clean | Native source clone preserved with a backup branch and stash. |
| S04 | Arch | Current branch | Four deferred entries | lazy-lock.json, Workmux command, Pi's no-final-newline serialization, and removal of the old Herdr installer target remain unresolved. |

## Installed-tool matrix

This is executable discovery, not a package-management declaration. WSL values
come from its initialized Zsh/Mise environment. Windows wt is Windows Terminal,
not Worktrunk.

| Tool group | Windows | WSL | macOS | Arch |
|---|---|---|---|---|
| Git and gh | Git; gh absent | Git and gh | Git and gh | Git and gh |
| Neovim and LazyGit | Both | Both | Both | Both |
| Herdr | Installed | Installed | Installed | Installed |
| OpenCode | Absent | Installed via Mise | Installed | Installed |
| Zsh | Absent | Installed | Installed | Installed |
| Starship | Not found in Git Bash PATH during inventory | Installed | Installed | Installed |
| Atuin, bat, bottom | Absent | Absent | Installed | Installed |
| LazyDocker, Posting | Absent | Absent | Installed | Installed |
| tmux, Workmux | Absent | tmux only | Both | Both |
| Worktrunk | Absent; wt means Windows Terminal | Absent | Absent | Installed |
| Yazi | Absent | Absent | Installed | Installed |
| Pi | Absent | Installed via Mise | Installed | Installed |
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
| D02 | Generic Linux | A non-Arch native Linux host receives only the small reviewed baseline. | Conservative | Should generic Linux follow Arch, WSL, or its own profile? |
| D03 | Source topology | Windows uses the working checkout. WSL, Mac, and Arch use native ~/.local/share/chezmoi clones. The normalization branch is local and is not pushed. | Intentional | Keep native clones but push the branch, or choose a different synchronization model? |
| D04 | Windows shell | Windows manages .bash_profile and .bashrc for Git Bash and ignores Zsh. | Required | Keep Git Bash as the native Windows shell? |
| D05 | Unix shells | WSL uses a small zshrc template; Mac and Arch use the larger Unix zshrc template. | Conservative | Merge these into one guarded Zsh baseline? |
| D06 | Zsh environment | WSL has only ~/.local/bin and OpenCode in its path template. Mac/Arch add Volta, Bun, Cargo, Go, and Composer paths. | Conservative | Share the larger path setup where tools exist? |
| D07 | Zsh plugins | WSL, Mac, and Arch share the same Antidote plugin list and ez-compinit loads first. | Intentional | Keep unified. |
| D08 | Shell aliases | common.sh supplies editor, Herdr, and LazyGit aliases everywhere it is managed. The larger Git/Yazi/tool alias set exists in the Mac/Arch Unix template; tmux and Workmux aliases render only on Arch. | Conservative plus explicit legacy decision | Which remaining aliases belong in common.sh? |
| D09 | Shell overlays | WSL sources .wsl.zsh, Mac sources .mac.zsh, and Arch sources .arch.zsh. | Required/intentional | Review each overlay and move only truly shared functions upward. |
| D10 | Project overlays | .greenlight.zsh, .vimme.zsh, and .ocprofile.zsh are managed on Arch but ignored on WSL, Mac, and Windows. Mac has live unmanaged copies. | Conservative | Should these be shared on Mac and/or WSL? |
| D11 | Private shell data | .private.zsh is ignored unless CHEZMOI_INCLUDE_SECRETS=1, and the deny-by-default profiles ignore it regardless. | Conservative | Define one explicit secret-management policy for every machine. |
| D12 | XDG root | Managed app configs use ~/.config. Windows sets XDG_CONFIG_HOME in Git Bash and as a user environment variable for Neovim. | Intentional | Keep. Existing long-lived Windows processes may need restart to see the environment variable. |
| D13 | Git common core | Name, email, default branch, pull behavior, excludes file, and ~/.config/git/local.config include are shared. | Intentional | Keep. |
| D14 | Git credentials | Only Arch writes explicit gh credential helpers for GitHub and Gist. | Historical | Use gh credential helpers everywhere gh is installed, or rely on each platform's native helper? |
| D15 | Git LFS | Git LFS filters are emitted for Windows, Mac, and Arch, but not WSL. | Conservative | Add WSL after confirming git-lfs installation? |
| D16 | Greenlight Git include | The ~/dev/greenlight include exists on Mac and Arch only. | Historical | Share it with other machines that contain that checkout? |
| D17 | lockb Git diff | Mac alone has a Bun textconv for lockb files. | Historical | Promote, remove, or retain as Mac-only? |
| D18 | Delta | Delta config and Catppuccin include were removed because Delta was not active. | Intentional during this pass | Reconsider only if Delta is deliberately adopted again. |
| D19 | Machine Git data | Arch stores its CodeRabbit machine ID and Pop!_OS mount include in unmanaged ~/.config/git/local.config, mode 0600. | Intentional | Keep machine IDs and machine paths out of the public source. |
| D20 | LazyGit | Arch/Mac render the Unix LazyGit template; Windows/WSL render the Neovim-oriented template. | Conservative | Decide whether the templates should converge. |
| D21 | GitHub CLI config | WSL, Mac, and Arch manage only ~/.config/gh/config.yml at mode 0600. Windows ignores it because gh is absent. hosts.yml is never managed. | Intentional | Install gh on Windows and share the same config? |
| D22 | SSH config | ~/.ssh/config and known_hosts remain completely unmanaged. | Explicit prior decision | Keep. |
| D23 | SSH keys | The old public-key file and 1Password-backed private-key template remain in source. Deny-by-default profiles ignore .ssh, so Arch is the only current profile that can manage them. | Historical/high priority | Remove legacy key management, or define a deliberate cross-machine key policy? |
| D24 | Starship | The same ~/.config/starship.toml is managed on all supported profiles. | Intentional | Keep. |
| D25 | Herdr core | The same core UI, theme, history, and navigation keys are managed on Windows, WSL, Mac, and Arch. | Intentional | Keep. |
| D26 | Herdr Windows terminal | Windows alone sets Git Bash as Herdr's shell, new_cwd=follow, and preview update channel. | Required/intentional | Review preview-channel preference separately from the shell requirement. |
| D27 | Herdr advanced commands | Popup launcher, directional splits, reordering, and Worktrunk actions render only on Arch. | Conservative | Enable subsets on Mac, WSL, or Windows after checking helper/plugin availability? |
| D28 | Herdr plugin subtree | Herdr plugin config and automatic plugin bootstrap are effectively Arch-only. | Conservative | Decide whether Mac should share the plugin set. |
| D29 | Herdr plugin installer | Source renamed ensure-herdr-plugins.sh to run_after_ensure-herdr-plugins.sh. Arch still has the old ~/ensure-herdr-plugins.sh target, so chezmoi reports R. Applying may also execute the installer. | Deferred actual drift | Review the script and plugin list before deleting the old target or running it. |
| D30 | Tunnel command | WSL uses systemd user services with tailscale/lan routes. Mac uses SSH ControlMaster sockets with tailscale/lan/remote routes. Windows and Arch do not receive tunnel. | Required | Keep separate implementations behind one command name. |
| D31 | Neovim ownership | Windows, WSL, and Arch manage the shared LazyVim tree. Mac has Neovim 0.12.4 installed but its config is deliberately ignored and remains independent. | Conservative/high priority | Bring Mac onto the shared Neovim tree? |
| D32 | Neovim platform guards | Windows uses LLVM, Git Bash shell settings, Node-launched Oxfmt, and a Windows markdown-preview installer. Unix uses Volta when present. FGA, tmux, Yazi, and Go integrations have executable/file guards. | Required/intentional | Keep guards; review whether any can simplify after ownership converges. |
| D33 | Neovim language support | TypeScript and Python were user-verified on the newly managed setup. Go tooling is skipped only when no Go executable is visible. | Intentional | Repeat verification on Mac if it joins the shared config. |
| D34 | Neovim lockfile | Arch's live lazy-lock.json differs from source for SchemaStore, Catppuccin, grug-far, mason-lspconfig, mini.move, Neogit, neotest-golang, nvim-lspconfig, nvim-treesitter, nvim-treesitter-textobjects, and Yazi. | Deferred actual drift | Choose source pins, Arch pins, or a coordinated Lazy update tested on all managed machines. |
| D35 | OpenCode ownership | WSL and Arch manage OpenCode. Mac has OpenCode installed but ignores its config. Windows has no OpenCode. | Conservative/high priority | Manage Mac too? |
| D36 | OpenCode default profile | WSL symlinks opencode.json to work.json. Arch symlinks it to personal.json. | Conservative choice made during this pass | Unify the default, or preserve a machine/profile distinction? |
| D37 | OpenCode version | WSL, Mac, and Arch have different installed OpenCode versions and installation methods. | Historical | Normalize installation/version management separately from config. |
| D38 | Workmux ownership | Workmux is preserved as Arch-only legacy configuration. Mac still has the Workmux executable installed, but its ~/.config/workmux directory was removed and its shell completion is no longer loaded. WSL does not have Workmux. | Explicit user decision | Keep the Arch source until eventual retirement. |
| D39 | Workmux command | Preserved Arch source config uses opencode --port. Arch live uses opencode. Both installed OpenCode versions document --port with default 0. | Deferred actual drift | Resolve only before the next Arch Workmux apply; this is no longer a cross-platform convergence issue. |
| D40 | Worktrunk | Worktrunk config, Herdr actions, and seeding helper are Arch-only; Mac and WSL lack Worktrunk. | Conservative | Install and share, or keep Arch-only? |
| D41 | tmux | tmux is preserved as Arch-only legacy configuration. Mac and WSL still have tmux installed. Mac's ~/.config/tmux directory, including downloaded TPM plugin clones, was removed; WSL's independent state remains untouched. | Explicit user decision | Keep the Arch source until eventual retirement. |
| D42 | Yazi | Mac and Arch manage Yazi. WSL and Windows ignore it. Mac renders open; Linux renders xdg-open. | Required plus conservative | Keep opener split; decide whether to install/share Yazi on WSL. |
| D43 | Atuin | Mac and Arch manage Atuin; WSL and Windows ignore it. | Conservative | Install/share on WSL and possibly Windows? |
| D44 | bat and bottom | Mac and Arch manage identical configs; WSL and Windows ignore them. bottom.toml is mostly a stock commented file. | Conservative/historical | Share tools, simplify the files, or remove inert config? |
| D45 | LazyDocker and Posting | Mac and Arch manage them; WSL and Windows ignore them. | Conservative | Decide whether these are workstation-only tools. |
| D46 | Pi ownership | Arch manages .pi. WSL and Mac both have Pi installed but ignore .pi; Windows lacks Pi. | Conservative/high priority | Share Pi extensions/settings, or split credentials/providers from portable extensions? |
| D47 | Pi current Arch state | Source now matches Arch's Pi 0.82.1 changelog state, pi-cursor-sdk package, staged-feedback trailing spacing, and pi-tui width handling for emoji-safe responsive rendering. Pi rewrites settings.json without a final newline, while source retains one. | Intentional plus benign drift | Treat changelog state as config or remove it from version control later? Do not churn the file merely to resolve the newline. |
| D48 | Agent skills | .agents is Arch-only. Mac has agent/cursor-agent executables but no ~/.agents directory; WSL and Windows ignore it. | Conservative | Share agent-review skill/config where the clients support it? |
| D49 | Local helper scripts | Arch manages the full ~/.local/bin helper collection. WSL and Mac manage only tunnel. Windows manages none. | Conservative/high priority | Classify helpers as portable, Unix-only, Arch-only, or obsolete. |
| D50 | macOS allowlist | Mac manages Git, gh config, LazyGit, Herdr core, Starship/common shell, Atuin, bat, bottom, LazyDocker, Posting, and Yazi. It intentionally no longer manages legacy tmux/Workmux. It also ignores Neovim, OpenCode, Pi, agents, project overlays, SSH, and all local helpers except tunnel. | Conservative choices plus explicit legacy decision | This remains the main list to reconsider if greater unification is desired. |
| D51 | WSL allowlist | WSL manages Git, gh config, LazyGit, Herdr core, Neovim, OpenCode, Starship/common shell, Zsh plugins, and tunnel. It ignores the remaining workstation tools and project overlays. | Conservative choice made during this pass | Decide which Mac/Arch tools should join the WSL baseline. |
| D52 | Windows allowlist | Windows manages Git, LazyGit, Herdr core, Neovim, Starship/common shell, and Git Bash startup. | Conservative | Decide whether to install/share gh or other native tools. |
| D53 | Nushell | A three-line 2021 TOML-era Nushell config was removed; Nushell was absent and modern Nushell no longer uses that format. | Intentional | Restore only if adopting modern Nushell with a new config. |
| D54 | Source documentation | docs is ignored by chezmoi so this inventory is not deployed into any home directory. | Intentional | Keep repository documentation outside target state. |
| D55 | Legacy shell integration | Mac no longer loads tmux/Workmux aliases or Workmux completion. Arch retains them. The Mac tmux and Workmux config directories were removed after the user confirmed they were unnecessary. | Explicit user decision | Preserve only the Arch legacy setup until eventual retirement. |

## Deferred actual changes

Do not run an unscoped chezmoi apply on Arch until these are reviewed:

1. ~/.config/nvim/lazy-lock.json: choose a canonical plugin lock.
2. ~/.config/workmux/config.yaml: choose opencode or opencode --port.
3. ~/.pi/agent/settings.json: ignore the harmless final-newline-only drift, or
   later redesign ownership of app-written state.
4. ~/ensure-herdr-plugins.sh: decide whether to delete the old target and
   whether the run-after installer should execute.

Windows, WSL, and Mac currently have no managed target drift.

## Rollback points

### Repository-level

- Windows branch: normalize/multi-platform.
- Mac backup branch: backup/mac-pre-normalization-20260727-034132.
- Mac stash: mac pre-normalization 20260727-034132.
- Arch backup branch: backup/arch-pre-normalization-20260727-034755.
- Arch stash: arch pre-normalization 20260727-034755.
- Arch also has an older unrelated stash named asdf; do not alter it casually.

### Windows

- C:/Users/Jeff Hertzler/.gitconfig.pre-xdg-20260727-032541
- Legacy Neovim rollback remains under LocalAppData from the Windows migration.

### WSL

- ~/.gitconfig.pre-xdg-20260727-072602
- ~/.zshrc.local.pre-chezmoi-20260727-072602
- ~/.config/herdr/config.toml.pre-chezmoi-20260727-073034
- ~/.config/gh/config.yml.pre-chezmoi-20260727-073554
- ~/.zsh_plugins.txt.pre-chezmoi-20260727-074721
- Previous Neovim tree: ~/.config/nvim.pre-chezmoi-20260727-070409

### macOS

- Config backups use timestamp 20260727-034417 for Git, gh, and Yazi.
- Shell/plugin backups use timestamps 20260727-034722 and 20260727-034734.
- Latest Mac Zsh legacy-gating backup uses timestamp 20260727-131806.
- Exact filenames are the original path plus .pre-chezmoi-TIMESTAMP.
- Mac ~/.config/tmux and ~/.config/workmux were deleted directly, not moved to
  Trash. Their configuration remains in the Arch-only source; TPM plugins can
  be reinstalled but the deleted plugin clones are not directly recoverable.

### Arch

- Git/gh/plugin backups use timestamp 20260727-034910.
- Zsh backup: ~/.zshrc.pre-chezmoi-20260727-034928.
- Neovim runtime backups use timestamp 20260727-035113.
- Pi settings backup uses timestamp 20260727-035234.
- Latest Arch Zsh legacy-gating backup uses timestamp 20260727-131806.

## Review order

1. D01 is decided: use shared application configs with explicit per-machine enablement.
2. D31, D35, D46, D49, D50, D51: decide which machines enable each application.
3. D05, D06, D08, D10: consolidate the active shell layers; leave legacy tmux/Workmux preserved on Arch.
4. D27, D28, D29, D40: consolidate Herdr and Worktrunk behavior.
5. D34 and D39: resolve the two live application drifts.
6. D14 through D23: finish Git, gh, SSH, and secret policy.

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
