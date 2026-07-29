# Pi Feedback v1.1: Combined Response and Code Feedback

## Status

Deferred plan for the next iteration. The current v1 workflow is complete and
supports manual composition: run `/feedback` first, then use `<leader>rs` in the
main Neovim to append code annotations to the staged Pi draft.

v1.1 would make that composition explicit and automatic without changing the
proven temporary-Neovim feedback UI.

## Goal

Let one `/feedback` operation produce a single Pi draft containing both:

1. transient feedback on the assistant's previous response; and
2. open code annotations from the active Agent Review session in the main
   Neovim instance.

The agent should receive one coherent turn while each source keeps its existing
lifecycle semantics.

## Proposed output

```markdown
# Feedback

## On your previous response

### feedback-1 — L12
> Quoted response text

Clarify this explanation.

## On the code

### review-7 — WORKING
- Target: `lua/example.lua:L42`
- Revision: `WORKING`
> Quoted code

This branch drops the original error.
```

The combined preamble should explain that `feedback-N` items are transient prose
feedback, while `review-N` items are persistent code annotations that the agent
must resolve through the `agent-review` CLI after addressing them.

## Lifecycle rules

The two annotation sources must remain distinct:

### Response feedback

- Uses isolated sidecar state in the temporary feedback workspace.
- Is consumed when Pi successfully stages the combined draft.
- Is discarded on ordinary quit unless the user explicitly keeps the draft.
- Uses operation-local `feedback-N` identifiers.

### Code feedback

- Remains in the main Neovim's normal Agent Review session.
- Is not removed or resolved merely because it was included in a Pi draft.
- Keeps its stable `review-N` identifiers, target metadata, revision, and anchor.
- Is resolved only after the agent addresses the code and runs
  `agent-review resolve ID...`.

This distinction avoids losing review state when a Pi draft is edited,
discarded, interrupted, or fails to submit.

## Recommended user experience

1. The user adds code annotations in the main Neovim as usual.
2. The user runs `/feedback` in Pi.
3. The temporary Neovim opens for response feedback.
4. After response feedback is submitted, Pi queries the active Agent Review
   session in the main Neovim.
5. If fresh open code annotations exist, Pi asks whether to include them and
   shows the session name and count.
6. Pi stages one combined draft. It does not submit automatically.

Potential command options:

```text
/feedback                 # detect code feedback and confirm inclusion
/feedback --code          # include active code feedback without confirmation
/feedback --response-only # skip code discovery
/feedback clear           # remove explicitly kept response-feedback drafts
```

Do not silently include annotations from `--all`, archived sessions, unrelated
workspaces, or a different Neovim server.

## Discovery and data flow

### Timing

Query code annotations after the temporary Neovim exits. While the temporary
process is running, its Agent Bridge server registration can be visible from the
same Herdr pane and should not be mistaken for the main editor.

### Read-only Agent Review access

Use the `agent-review` CLI rather than raw Neovim RPC:

1. `agent-review context` identifies the selected main Neovim server, current
   workspace, and active review session.
2. `agent-review list` returns the active session's structured annotations.
3. Filter to open, fresh human annotations using the same rules as normal Agent
   Review export.

The Pi extension should execute commands without a shell, set a short timeout,
validate the JSON schema, and bound the number and size of comments.

If formatting the code section in TypeScript would duplicate too much of
`agent_review.export`, add a read-only `agent-review export` command/RPC operation
that returns the active session's Markdown payload or a structured export model.
Do not reach into the persistence JSON file directly.

### Failure behavior

Code-feedback discovery is additive. If the CLI is unavailable, no main Neovim
is running, JSON is invalid, or discovery is ambiguous:

- keep the response-feedback draft;
- notify the user that code feedback was not included; and
- preserve the manual `<leader>rs` fallback.

A code-discovery failure must never discard submitted response feedback.

## Prompt construction

Build one top-level prompt rather than concatenating two independent prompts.
This avoids duplicate headings and conflicting instructions.

The code section must preserve:

- Agent Review annotation ID;
- repository root;
- active session ID;
- file and one-based line/UTF-8 byte-column range;
- side and selected revision;
- freshness and status;
- exact anchored text; and
- comment body and kind.

Include the main Neovim server identity or enough Agent Review context for the
agent to target the correct session when resolving comments.

## Scope and non-goals

### In scope

- Active-session code annotations from one unambiguous main Neovim.
- One confirmation before including detected code feedback.
- One combined, editable Pi draft.
- Graceful response-only fallback.
- Existing manual composition remains supported.

### Out of scope

- Collecting annotations across all Agent Review workspaces or sessions.
- Automatically resolving or deleting code annotations.
- Opening code files in the temporary feedback Neovim.
- Reusing an existing Neovim for the response UI; that is the separate v2 plan.
- Automatically submitting the combined draft.

## Edge cases

- **No code annotations:** preserve the current response-only behavior without an
  extra prompt.
- **Only resolved or stale annotations:** treat as no includable code feedback.
- **Multiple Neovim candidates:** ask the user or skip; never guess across
  unrelated workspaces.
- **Session changes during feedback:** show the final detected session name and
  require confirmation rather than silently using an earlier snapshot.
- **Main Neovim exits:** stage response feedback and warn that code feedback was
  omitted.
- **Large annotation sets:** enforce a bounded count/size and direct the user to
  split the review.
- **Duplicate staging:** include each code annotation once in the generated
  draft; do not mutate its persistent Agent Review status.
- **Unicode ranges:** retain Agent Review's one-based UTF-8 byte-column
  convention.

## Suggested implementation phases

1. **Extractor:** add a tested TypeScript adapter for `agent-review context` and
   `agent-review list`, including timeout and schema validation.
2. **Formatter:** produce a combined prompt from response feedback plus a
   structured code-annotation snapshot.
3. **UX:** add detection, confirmation, and `--code` / `--response-only` options.
4. **Lifecycle:** verify response state is consumed while code annotations remain
   open and resolvable.
5. **Fallbacks:** test missing CLI, no server, ambiguity, process exit, stale
   annotations, and oversized payloads.
6. **Documentation:** describe automatic and manual composition workflows.

## Acceptance criteria

- `/feedback` with no code annotations behaves exactly like v1.
- Detected code feedback is included only after confirmation unless explicitly
  requested by an option.
- The staged draft has one coherent heading and separate response/code sections.
- Response annotations are consumed after staging.
- Code annotations remain visible and open in the main Neovim.
- The agent can resolve included `review-N` IDs after editing code.
- Discovery failure leaves a valid response-only draft and clear notification.
- Manual `/feedback` then `<leader>rs` composition still works.

## Recommendation

Implement this before existing-Neovim reuse. It adds direct workflow value while
preserving the simple v1 process boundary and avoids the state-isolation and
focus-management risks described in [`FEEDBACK_V2.md`](./FEEDBACK_V2.md).
