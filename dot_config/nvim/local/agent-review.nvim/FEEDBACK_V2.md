# Pi feedback: existing-editor readers

Implemented. This replaces the earlier deferred design for a blocking floating
editor and completion handshake. See [README.md](./README.md#pi-feedback) for
mappings, the Lua RPC contract, and restart requirements.

## Current behavior

- Each Pi catalogue owns a reader tab. Multiple conversations and ordinary code
  review coexist in one Neovim process. Dedicated standalone readers still work.
- Replies are immutable Markdown snapshots. Catalogue updates never replace the
  text or move the cursor in the current reply.
- Each feedback message owns its annotations, sessions, and persistence.
  `agent_review.context` selects storage from buffer metadata; navigation does
  not change a process-global store or environment variable.
- Annotation editors retain the originating context across buffer switches.
  Background rendering and debounced writes use their associated context.
- Submit uses the existing Agent Bridge staging path: paste into the agent input
  at its cursor, focus the agent, then close only the originating feedback view.
  Existing input is not cleared and Enter is not pressed. Failed or cancelled
  staging keeps the view and drafts open. Reading and ordinary closing send nothing.
- Ordinary `:q` retains drafts. Keep closes only the owned reader view in a
  shared editor. Discard removes only the current message's annotations and
  payload, not its source or metadata.
- Closing stops the reader's poller, flushes drafts, and invalidates pending
  annotation accepts and saves. Hidden buffers can be reused on reopening.
  Remote `status` reports `open=false` only after file-writing callbacks are
  inactive; a failed final save keeps the catalogue protected.
- The parent discovers suitable editors in the live Herdr workspace. The plugin
  accepts `open`, `focus`, and read-only `status` requests keyed by catalogue
  path. It does not discover editors or control Pi panes.

Running Neovim instances must restart after installation. The version marker
`require('agent_review').feedback_context_version == 1` prevents new reader
files from running against an old loaded global-store implementation. Do not
hot-reload Agent Review modules.
