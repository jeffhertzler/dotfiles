# agent-diff.nvim

A buffer-first Git diff frontend using CodeDiff's C diff engine without
CodeDiff's tab-based UI.

## Direct views

- `:AgentDiff [revision]` toggles an inline diff in the current editable buffer.
- `:AgentDiffSide [revision]` toggles a current-tab side-by-side diff.
- Repeating the active mode's command closes the diff.
- `:AgentDiffToggle` switches an active diff between layouts.
- `:AgentDiffRefresh` reloads the baseline and recomputes the diff.
- `:AgentDiffClose` clears the view.
- `:AgentPatch` or `<leader>gw` toggles the current file's patch workspace.

`HEAD` is the default baseline. `INDEX` compares against the Git index.

## Changesets and files

Neogit's real `d` popup is backed by Agent Diff. Status-file `dd` remains a
single-file operation. Unstaged, staged, worktree, commit, stash, and range
operations resolve a changeset. The file sidebar opens by default only when the
resolved changeset contains more than one file.

Diff views leave the existing winbar untouched. Press `?` for a rounded help
popup listing the available controls. Inside every diff view:

- Repeat `<leader>gd` for inline or `<leader>gD` for side-by-side to close it;
  `:AgentDiffClose` always closes either layout.
- `<leader>b` opens or closes the file sidebar.
- `]f` and `[f` move to the next or previous file.
- `<CR>` in the sidebar selects a file.

Direct single-file views start with the sidebar hidden and resolve the matching
changeset lazily if it is opened. No view creates a tab page.

## Patch workspace

`<leader>gw` opens bottom-aligned floating patch panes for the current file.
`Unstaged` (`INDEX → WORKING`) and `Staged` (`HEAD → INDEX`) are separate rounded
popups, with unstaged above staged when both exist. Empty panes are hidden.
Patch loading and Git application are asynchronous; source syntax plus CodeDiff
line and character refinement remain visible, and every patch row is
cursor-addressable. A missing destination pane appears immediately while Git
finishes, and the current pane keeps focus as long as it still has changes.

- `Tab` and `Shift-Tab` switch between the unstaged and staged popups.
- The workspace starts in hunk mode; `a` toggles hunk/line mode, matching LazyGit.
- `Space` stages or unstages the current hunk or changed line according to that mode.
- Visual `Space` applies the operation to selected patch lines regardless of mode.
- `dd` unstages a staged hunk or confirms before discarding an unstaged hunk.
- Visual `d` operates on selected patch lines.
- `[h` and `]h` navigate hunks; `r` refreshes; `<Esc>` or `q` closes.
- `?` opens the rounded controls popup.
- Agent Review's normal `<leader>ra` mapping attaches directly to exact old,
  index, or working rows, including deleted lines.

The panel refreshes after each operation so changes move between the staged and
unstaged sections while the editable whole-file view remains visible above.
Deferred edge cases and polish are tracked in
[`PATCH_WORKSPACE_ROADMAP.md`](PATCH_WORKSPACE_ROADMAP.md).

Working-file edits made by an external agent are reloaded and recomputed while
the buffer has no unsaved local changes. External index changes refresh the
active Neogit changeset and its file sidebar. If the buffer is modified, Agent
Diff warns instead of overwriting it. Computation uses bounded initial/live
budgets and retains the available result when character refinement times out.
For pathological rewrites, virtual old text skips Tree-sitter parsing so the
renderer does not erase the computation time bound.

Neogit follows Git's `status.showUntrackedFiles` setting. Set it to `all` when
individual files inside untracked directories should be listed:

```sh
git config --global status.showUntrackedFiles all
```

Gitsigns' inline hunk preview uses the same engine. Neogit expanded hunks use
CodeDiff's range calculation and `CodeDiffCharInsert`/`CodeDiffCharDelete`
inner colors while preserving Neogit's line backgrounds and Tree-sitter
foregrounds. Native Gitsigns and Neogit hunks remain canonical for staging,
resetting, and navigation.
