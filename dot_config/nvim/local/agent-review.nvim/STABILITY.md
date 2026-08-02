# Agent Review stability checkpoint

This file records the supported behavior before VCS provider integration.

## Supported user behavior

- Annotate line or characterwise line/column ranges in ordinary editable buffers.
- Add and edit multiline comments through the shared compact Agent input UI.
- Edit, resolve/reopen, remove, list, navigate, and send annotations.
- Persist workspaces, named sessions, archival state, anchors, and active-session
  selection outside repositories.
- Reanchor exact moved content and mark changed or ambiguous content stale.
- Render matching working and revision-side annotations through CodeDiff,
  including old-side inline deletion blocks.
- Accept transactional agent batches through Neovim RPC and render incoming
  annotations immediately in visible matching buffers.
- Anchor working-file findings from disk even when their files are unopened.

## Public boundaries

The Neovim command surface is `:AgentReview` with subcommands. The public Lua
surface is the namespaced API returned by `require("agent_review")`, documented
in `README.md`.

Agents use the `agent-review` executable. Its implementation calls the
independently versioned `require("agent_review.rpc").dispatch(request)` boundary.
RPC wire schema is v1; on-disk persistence is schema v2.

AgentBridge remains the one-way dependency for shared input, composing, target
selection, socket publication, and transport. AgentBridge does not depend on or
own Agent Review state.

## Explicitly deferred

- fuzzy reanchoring of edited selected text;
- blockwise annotation targets;
- direct cursor/column selection inside CodeDiff virtual deletion rows;
- threads and replies;
- forge synchronization;
- offline bundle formats.

## Tests

Run from the chezmoi source tree:

```sh
bash dot_config/nvim/local/agent-review.nvim/tests/run.sh
```

The isolated suite covers the review input adapter, regular buffers, columns,
CRUD, command/API boundaries, transactional RPC, unopened-file anchoring,
AgentBridge send integration, persistence/restart, v1 migration,
reanchoring/stale state, named sessions, and CodeDiff and Agent Diff adapters.
Generic AgentBridge input, context, and command behavior is covered by
AgentBridge's own suite; Agent Diff's standalone views and patch behavior are
covered by Agent Diff's suite.
