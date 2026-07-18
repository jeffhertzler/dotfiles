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
| `<leader>re` / `:NativeReviewEdit`          | Edit the annotation at the cursor       |
| `<leader>rl` / `:NativeReviewList`          | List annotations; `e` edits, `d` removes |
| `<leader>rs` / `:NativeReviewSend`          | Stage all open notes in the selected agent |
| `:NativeReviewSend!`                        | Send, submit, and keep focus in Neovim  |
| `:NativeReviewCompose`                      | Open Agent Prompt with review context   |
| `:NativeReviewAdd`                          | Annotate the current line               |
| `:NativeReviewEdit review-3`                | Edit an annotation by ID                |
| `:NativeReviewRemove review-3`              | Remove an annotation by ID              |
| `:NativeReviewClear`                        | Clear all in-memory annotations         |

## Agent RPC import

The outbound review payload includes this Neovim instance's RPC server. Agents
can validate and atomically import a batch with:

```lua
require("native_review.rpc").apply({
  schemaVersion = 1,
  author = "pi",
  comments = {
    {
      id = "agent-finding-1",
      body = "This branch loses the original error.",
      kind = "issue",
      target = {
        file = "lua/example.lua",
        side = "working",
        startLine = 42,
        startCol = 8, -- optional; requires endCol
        endLine = 42,
        endCol = 19,
        columnEncoding = "utf-8-byte",
      },
    },
  },
})
```

RPC-facing operations are available through `native_review.rpc`:

- `context()` returns the current buffer/repository and server address.
- `list()` returns annotations in the versioned wire format.
- `apply(payload)` validates the full batch before adding anything.
- `dispatch({ operation = ... })` provides a single RPC entry point.

For shell-based agents, write the payload to a JSON file and evaluate
`native_review.rpc.apply` through `nvim --server <socket> --remote-expr`. Imported
annotations are marked as agent-authored and use distinct rendering.

## Spike limitations

- State is intentionally in memory and is lost when Neovim exits.
- Annotation input is single-line for now.
- Old-side notes are preserved but not yet rendered in inline layout.
- Blockwise selections are not implemented.
- Diff-side picker navigation expects the relevant CodeDiff file to be selected.
- Resolving, agent annotation import, and durable reanchoring are later phases.
