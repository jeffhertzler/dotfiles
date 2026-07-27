# Patch Workspace Roadmap

The core tracked-text-file workflow is implemented. These follow-ups are intentionally deferred until the current interaction model has had real-world use.

## File and diff edge cases

- [ ] Support untracked and newly added files, including partial staging from an empty index entry.
- [ ] Support deleted files and partial restoration where Git permits it.
- [ ] Preserve rename/copy metadata and operate on the correct old and new paths.
- [ ] Represent binary changes without pretending they have selectable text rows.
- [ ] Handle executable-bit and other mode-only changes.
- [ ] Define safe behavior when the working buffer contains unsaved edits; never stage or discard content different from what the popup displays.

## Interaction polish

- [ ] Reposition and resize both floating panes on `VimResized` while preserving focus and scroll position.
- [ ] Preserve a logical cursor anchor across refreshes using section, hunk identity, side, and source line instead of only the screen row.
- [ ] Add a small, non-blocking busy indicator to an already-visible pane during Git operations.
- [ ] Add undo for the last stage, unstage, or discard operation by retaining and safely reversing the exact applied patch.
- [ ] Decide whether undo should be a single operation or a bounded per-workspace stack.

## Robustness and performance

- [ ] Keep popup creation and key handling non-blocking for large files and repositories.
- [ ] Cache or incrementally refresh source syntax and CodeDiff refinement when hunks move between panes.
- [ ] Reject stale operations cleanly when the index or working tree changes after rendering.
- [ ] Add regression coverage for every file type above, pane resizing, cursor anchoring, undo, operation failures, and concurrent external Git changes.

## Current invariants to preserve

- `Unstaged` and `Staged` remain separate rounded panes.
- `Tab` switches panes; `a` toggles hunk/line mode; `Space` applies the active mode.
- Git operations do not force focus into the destination pane.
- Empty panes disappear, and a destination pane may appear optimistically while Git finishes.
- Deleted rows remain cursor-addressable and support exact Agent Review annotations.
- Agent Diff's editable whole-file view and Neogit's parked status lifecycle remain intact.
