# native-review.nvim

Early buffer-first spike for native human and agent annotations. See the broader
architecture in
[`../agent-bridge.nvim/REVIEW_PLAN.md`](../agent-bridge.nvim/REVIEW_PLAN.md).

CodeDiff is an optional adapter. Creating, rendering, tracking, listing, and
navigating working-file annotations does not require a diff view.

## Current functionality

- Adds human notes directly to regular file buffers.
- Shows a working-file note on the matching CodeDiff working side.
- Adds revision-aware notes to old/new CodeDiff buffers.
- Normal-mode annotations target a line.
- Characterwise visual annotations retain optional byte columns.
- Notes render as virtual-line boxes with signs and target highlighting.
- Extmark anchors follow ordinary edits during the live Neovim session.
- Notes are restored on buffer entry and CodeDiff lifecycle events.
- Working buffers remain editable.

## Usage

| Mapping/command                             | Action                                  |
| ------------------------------------------- | --------------------------------------- |
| `<leader>ra`                                | Annotate the current line               |
| visual `<leader>ra`                         | Annotate the selected line/column range |
| `<leader>rd` / `:NativeReviewRemove`        | Remove the annotation at the cursor     |
| `<leader>rl` / `:NativeReviewList`          | List annotations; `d` removes one       |
| `:NativeReviewAdd`                          | Annotate the current line               |
| `:NativeReviewRemove review-3`              | Remove an annotation by ID              |
| `:NativeReviewClear`                        | Clear all in-memory annotations         |

## Spike limitations

- State is intentionally in memory and is lost when Neovim exits.
- Annotation input is single-line for now.
- Old-side notes are preserved but not yet rendered in inline layout.
- Blockwise selections are not implemented.
- Diff-side picker navigation expects the relevant CodeDiff file to be selected.
- Editing, resolving, agent import/export, and durable reanchoring are later
  phases.
