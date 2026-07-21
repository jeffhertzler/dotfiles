---
name: agent-review
description: Use Agent Review to read, create, update, resolve, remove, and refresh persistent Neovim review annotations through the agent-review CLI. Use when a prompt contains Agent Review annotation IDs, asks you to address review comments, or asks you to add findings to the user's live Neovim buffers.
---

# Agent Review

Use the `agent-review` CLI. Do not construct raw `nvim --remote-expr` Lua.

## Workflow

1. Run `agent-review context` to confirm the workspace, active session, and selected revision.
2. Run `agent-review list` to read current-session annotations.
3. Preserve human annotation IDs while editing the requested files.
4. After external file edits, run `agent-review refresh` so Neovim reloads and reanchors visible annotations.
5. Resolve human annotations only after addressing them: `agent-review resolve ID...`.
6. Add agent findings atomically with `agent-review apply --stdin`.
7. Remove agent annotations only when they are invalid or the user requests removal.

Use `agent-review list --all` only when the user explicitly asks for cross-session or cross-workspace state.

## Applying findings

Pass JSON on stdin:

```sh
agent-review apply --stdin <<'JSON'
{
  "schemaVersion": 1,
  "author": "pi",
  "comments": [
    {
      "id": "agent-finding-1",
      "body": "This branch drops the original error.",
      "kind": "issue",
      "target": {
        "file": "lua/example.lua",
        "side": "working",
        "startLine": 42,
        "endLine": 42,
        "columnEncoding": "utf-8-byte"
      }
    }
  ]
}
JSON
```

Targets use one-based lines and one-based UTF-8 byte columns. `startCol` and
`endCol` must be supplied together. Use the active session returned by
`context`; include `sessionId` only when targeting another known session.

Operations are transactional: if validation fails, correct the payload and
retry rather than applying findings individually.
