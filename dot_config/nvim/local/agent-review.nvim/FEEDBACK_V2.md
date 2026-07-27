# Pi Feedback v2: Reuse an Existing Neovim

## Status

Deferred design note. The current `/feedback` workflow is complete and remains
the default: Pi opens a temporary Neovim process, feedback state is isolated in
the temporary workspace, and submit/discard gives Pi a deterministic completion
signal.

Only pursue v2 if temporary Neovim startup or pane switching becomes a recurring
source of friction.

## Goal

When a suitable Neovim instance already exists in the same Herdr workspace,
open the feedback UI there instead of starting another process. Preserve the
current temporary-Neovim path as a reliable fallback.

## Tradeoffs

| | Temporary Neovim (v1) | Existing Neovim (possible v2) |
| --- | --- | --- |
| Startup | Pays Neovim startup cost | Nearly immediate |
| Editor context | Separate process | Reuses theme, clipboard, and active editor |
| State isolation | Natural through `NVIM_AGENT_REVIEW_STATE` | Requires a new isolated state mechanism |
| Completion | Child-process exit is definitive | Requires an asynchronous handshake |
| Focus | Pi automatically resumes after child exit | Must move to Neovim and restore Pi explicitly |
| Failure handling | Small, local surface | Server death, stale UI, routing, and retries |
| Multiple editors | Irrelevant | Must select the correct server and pane |
| Maintenance | Low | Higher cross-process lifecycle complexity |

### Benefits

- Avoid Neovim startup latency.
- Keep familiar editor context, clipboard state, theme, and keymaps.
- Make feedback feel like a native overlay on the existing coding workspace.
- Avoid temporarily replacing the Pi terminal contents.

### Costs and risks

- **Reverse discovery:** Pi must find Neovim servers, map them to Herdr panes,
  prefer the same tab/workspace, and handle multiple candidates.
- **Asynchronous completion:** remote RPC returns after opening the UI, not when
  feedback is finished. Pi needs a watched completion artifact or socket
  protocol for submit, keep, discard, and failure.
- **Focus ownership:** opening feedback must focus Neovim; every completion and
  error path must restore the original Pi pane without stealing focus later.
- **State isolation:** an existing Neovim already has Agent Review persistence
  loaded. Changing `NVIM_AGENT_REVIEW_STATE` is process-wide and therefore not
  available. Feedback annotations must not enter or race with normal review
  state.
- **UI restoration:** a floating window must survive resize and nested annotation
  input, then restore the previous tab, window, cursor, and focus exactly.
- **Concurrency:** duplicate `/feedback` calls, stale overlays, Pi shutdown,
  Neovim shutdown, and `/reload` need explicit ownership and cleanup rules.
- **Fallback behavior:** discovery or RPC failure must transparently use the v1
  temporary process without losing the requested feedback session.

## Proposed architecture

### Pi side

1. Add a mode setting such as `PI_FEEDBACK_MODE=auto|temporary|existing`, with
   `auto` as the eventual default and `temporary` as the escape hatch.
2. Discover Neovim candidates from the existing Agent Bridge server registry and
   Herdr workspace/tab metadata.
3. Prefer one unambiguous same-tab candidate; prompt when multiple equally good
   candidates exist.
4. Create the normal feedback workspace and metadata, including the originating
   Pi pane ID and a unique operation ID.
5. Invoke a narrow Neovim RPC entry point such as
   `require("agent_review.feedback").open(metadata)`.
6. Keep a lightweight Pi custom component active while asynchronously watching
   an atomically written completion file.
7. Parse `submit`, `keep`, `discard`, or `error`, restore Pi focus, and stage the
   prompt exactly as v1 does.
8. Fall back to temporary Neovim if discovery, RPC, or initial focus fails.

### Neovim side

1. Open a full-screen floating feedback buffer in the existing process.
2. Record the prior tab, window, cursor, and focused Herdr pane.
3. Use a feedback-specific in-memory annotation store and sidecar persistence,
   while reusing Agent Review capture, input, and rendering primitives.
4. Keep all mappings buffer-local and preserve the current v1 lifecycle:
   submit consumes, ordinary quit discards, and keep is explicit.
5. Atomically write a completion artifact before closing the UI.
6. Restore the original Neovim UI, then focus the originating Pi pane.

A dedicated transient-state adapter is preferable to temporarily inserting
feedback annotations into normal Agent Review state. The latter risks global
persistence races and review-status pollution.

## Completion protocol

Use one atomically renamed JSON file keyed by operation ID:

```json
{
  "schemaVersion": 1,
  "operationId": "...",
  "outcome": "submit",
  "feedbackPath": "...",
  "completedAt": "..."
}
```

Allowed outcomes:

- `submit`: feedback payload is complete and should be staged in Pi.
- `keep`: sidecar annotations remain available as a draft.
- `discard`: remove the feedback workspace.
- `error`: retain enough diagnostic information for fallback or recovery.

Pi should ignore completion files with the wrong operation ID and treat writes
as valid only after atomic rename.

## Suggested implementation phases

1. **Discovery spike:** locate and focus the correct existing Neovim, open a
   disposable read-only buffer, and restore focus.
2. **Handshake:** implement operation IDs, completion watching, cancellation,
   timeout, and server-death handling without annotations.
3. **Transient annotations:** separate Agent Review capture/render/input from its
   global persisted state and connect the sidecar feedback store.
4. **Fallback and recovery:** retain v1, add stale-operation cleanup, and test
   duplicate requests and process exits.
5. **Polish:** resize behavior, candidate selection, status text, and optional
   configuration.

## Acceptance criteria

- Auto mode adds no regressions to the temporary-Neovim workflow.
- Feedback annotations never appear in normal Agent Review sessions or status.
- Submit, keep, discard, `:q`, Pi exit, Neovim exit, and `/reload` have
  deterministic cleanup behavior.
- Focus returns to the originating Pi pane only when the feedback operation owns
  it.
- Multiple Neovim instances are handled without silently choosing an unrelated
  workspace.
- RPC or focus failure falls back to temporary Neovim without losing content.

## Recommendation

Keep v1 unless real-world use shows that startup latency outweighs the added
routing, state, and lifecycle complexity. Implement the combined-feedback work
in [`FEEDBACK_V1_1.md`](./FEEDBACK_V1_1.md) first. If v2 is implemented, build
the isolated annotation adapter before making existing-Neovim mode the default.
