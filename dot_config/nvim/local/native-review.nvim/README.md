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
- Human and agent annotations persist across Neovim restarts.
- Add/edit/resolve/remove/import operations are autosaved atomically.
- Working buffers remain editable.

## Usage

| Mapping/command                             | Action                                  |
| ------------------------------------------- | --------------------------------------- |
| `<leader>ra`                                | Annotate the current line               |
| visual `<leader>ra`                         | Annotate the selected line/column range |
| `<leader>rd` / `:NativeReviewRemove`        | Remove the annotation at the cursor     |
| `<leader>re` / `:NativeReviewEdit`          | Edit the annotation at the cursor       |
| `<leader>rl` / `:NativeReviewList`          | List active-session annotations          |
| `<leader>rs` / `:NativeReviewSend`          | Stage active-session open notes          |
| `:NativeReviewSend!`                        | Send, submit, and keep focus in Neovim  |
| `:NativeReviewCompose`                      | Open Agent Prompt with review context   |
| `:NativeReviewAdd`                          | Annotate the current line               |
| `:NativeReviewEdit review-3`                | Edit an annotation by ID                |
| `:NativeReviewRemove review-3`              | Remove an annotation by ID              |
| `:NativeReviewListAll`                      | List annotations across all workspaces  |
| `:NativeReviewWorkspaces`                   | Browse workspace annotation groups      |
| `:NativeReviewSessions`                     | Browse and switch review sessions       |
| `:NativeReviewSessionNew [name]`            | Create and activate a named session     |
| `:NativeReviewSessionSwitch <id>`           | Activate a session by ID                |
| `:NativeReviewSessionArchive [id]`          | Archive the active session or an ID     |
| `:NativeReviewSessionClear`                 | Clear active-session annotations        |
| `:NativeReviewSendAll[!]`                   | Send annotations across all workspaces  |
| `:NativeReviewPrune[!]`                     | Prune resolved; bang also prunes stale  |
| `:NativeReviewClearCurrent`                 | Clear the current workspace             |
| `:NativeReviewClear`                        | Clear all persisted annotations         |
| `:NativeReviewSave`                         | Flush annotations to disk               |
| `:NativeReviewReload`                       | Reload annotations from disk            |

## Workspace scoping

Normal list/send/cleanup operations are scoped to the current repository root.
Plain files without a detected Git or JJ root use a file-specific scope. This
prevents annotations from unrelated projects from being sent together.

`:NativeReviewWorkspaces` opens a compact picker showing open, resolved, and
stale counts for each scope. Selecting one opens its sessions. Resolved
annotations can be pruned from only the current workspace; `:NativeReviewPrune!`
also removes stale annotations. Explicit `All` commands remain available when a
cross-workspace operation is intentional.

## Named sessions and archival

Each workspace has one active review session. New annotations and normal
list/send operations belong to that session. `:NativeReviewSessionNew My pass`
starts a separate review without deleting earlier notes. Sessions capture the
workspace, backend, and base/target revision expressions present at creation.

`:NativeReviewSessions` shows active (`●`), inactive (`○`), and archived (`□`)
sessions with annotation counts. `<CR>` activates a session and `a` archives or
restores it. Archived sessions and annotations remain persisted but are hidden
from normal rendering and outbound payloads. They can be restored without data
loss.

## Persistence

State uses a versioned JSON document at:

```text
stdpath("state")/native-review/annotations.json
```

Writes are debounced, atomic, and permissioned `0600`. Persistence schema v2
stores sessions, active-session selections, and annotations across multiple
repositories and plain files without creating repository artifacts. Schema v1
annotation files migrate automatically. Invalid or unsupported state files are
reported and preserved rather than overwritten on exit.

## Reanchoring and freshness

Persisted annotations retain selected text plus nearby lines. When a buffer is
opened or written, the target is classified as:

- `fresh`: the selected content still matches at its tracked position;
- `reanchored`: the exact content moved and was uniquely located, using nearby
  context to disambiguate duplicates;
- `stale`: the content changed, disappeared, or has an ambiguous new location.

Line ranges and single- or multi-line character ranges are supported. Stale
annotations stay visible with warning styling at their saved location, are
rechecked after writes, and are excluded from outbound agent payloads by
default. Reanchored positions and freshness are persisted.

Tests and isolated instances can override the path with
`NVIM_NATIVE_REVIEW_STATE` or setup options:

```lua
require("native_review").setup({
  persistence = {
    enabled = true,
    path = "/custom/annotations.json",
    debounce_ms = 100,
  },
})
```

## Agent RPC import

The outbound review payload includes this Neovim instance's RPC server. Agents
can validate and atomically import a batch with:

```lua
require("native_review.rpc").apply({
  schemaVersion = 1,
  author = "pi",
  sessionId = "session-2", -- optional; defaults to the active session
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
- `update({ updates = { ... } })` changes bodies, kinds, or statuses by ID.
- `resolve({ ids = { ... } })` marks a validated batch resolved.
- `remove({ ids = { ... } })` deletes a validated batch.
- `refresh()` revalidates visible annotations after external edits.
- `dispatch({ operation = ... })` provides a single RPC entry point.

For shell-based agents, write the payload to a JSON file and evaluate
`native_review.rpc.apply` through `nvim --server <socket> --remote-expr`. Imported
annotations are marked as agent-authored and use distinct rendering. Resolved
annotations remain visible but are dimmed and excluded from outbound payloads.

## Spike limitations

- Annotation input is single-line for now.
- Old-side notes are preserved but not yet rendered in inline layout.
- Blockwise selections are not implemented.
- Diff-side picker navigation expects the relevant CodeDiff file to be selected.
- Reanchoring currently requires the originally selected text to remain exact;
  fuzzy matching for edited selections is not implemented.
