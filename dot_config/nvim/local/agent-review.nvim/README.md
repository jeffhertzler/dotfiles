# agent-review.nvim

Buffer-first, persistent human and agent review annotations for ordinary Neovim
buffers. CodeDiff is an optional revision/diff adapter; AgentBridge supplies the
shared input UI, composer, agent target selection, and transport.

See [`STABILITY.md`](./STABILITY.md) for the supported surface and
[`../agent-bridge.nvim/REVIEW_PLAN.md`](../agent-bridge.nvim/REVIEW_PLAN.md) for
the broader architecture.

## Human workflow

| Mapping | Action |
| --- | --- |
| `<leader>ra` | Add a line annotation |
| visual `<leader>ra` | Annotate the selected line/column range |
| `<leader>rA` | Select and annotate a deleted line in an inline diff |
| `<leader>rd` | Remove the annotation at the cursor |
| `<leader>rc` | Clear all annotations in the active review session |
| `<leader>re` | Edit the annotation at the cursor |
| `<leader>rl` | Open the active-session picker |
| `<leader>rs` | Stage active-session feedback for an agent |

The picker uses `<CR>` to navigate, `e` to edit, `r` to resolve/reopen, and `d`
to remove. Lualine shows `Review current/total` whenever the active session has
open annotations; clicking it opens the picker.

Annotation add/edit uses a compact bordered Markdown buffer. It starts one line
tall and grows to eight lines. `<CR>` inserts a newline in insert mode,
`<C-s>` or `<M-s>` saves, `<Esc>` leaves insert mode, normal `<CR>` saves, and
normal `<Esc>`, `q`, or `<C-c>` cancels.

## Command

All command interactions live under one command with completion:

```vim
:AgentReview
:AgentReview add
:AgentReview add old
:AgentReview list [--all]
:AgentReview edit [id]
:AgentReview resolve [id]
:AgentReview reopen [id]
:AgentReview remove [id]
:AgentReview send [--submit] [--all]
:AgentReview compose [--all]

:AgentReview session [list]
:AgentReview session new [name]
:AgentReview session switch <id>
:AgentReview session archive [id]
:AgentReview session clear

:AgentReview workspace [list]
:AgentReview workspace clear
:AgentReview prune [--stale] [--all]
:AgentReview clear --all
```

`:AgentReview` with no arguments opens the active review picker.

## Diff hosts

Agent Diff is the primary buffer-first host. It uses CodeDiff's C engine while
keeping the working buffer editable and toggling inline/current-tab split
layouts without tab pages. Working and revision-side annotations render in both
layouts. The full CodeDiff host remains supported as an optional adapter.

Old-side annotations project beside the corresponding virtual deletion block in
inline views. To create one inline, put the cursor on an added replacement line
or the real line adjacent to a pure deletion and press `<leader>rA`; select the
exact deleted line when prompted. `:AgentReview add old` provides the same flow.

Virtual deletion rows cannot receive a Neovim cursor, so the comment box
attaches to the containing block rather than an exact virtual row.

## Sessions and persistence

Each repository or plain-file workspace has one active named session. Normal
render/list/send operations use only that session. Earlier sessions may be
archived and restored without deleting their annotations.

State is written atomically with `0600` permissions to:

```text
stdpath("state")/agent-review/annotations.json
```

Tests may override this with `NVIM_AGENT_REVIEW_STATE`. Anchors retain selected
text and surrounding context. Exact moved content is reanchored; changed or
ambiguous content becomes stale and is excluded from outbound feedback.

## Lua API

```lua
local review = require("agent_review")

review.annotation.add(opts)
review.annotation.add_old(opts)
review.annotation.edit(id, opts)
review.annotation.remove(id)
review.annotation.resolve(id)
review.annotation.reopen(id)
review.annotation.get(id)
review.annotation.list(opts)

review.session.current()
review.session.list(workspace, opts)
review.session.create(name)
review.session.activate(id)
review.session.archive(id)
review.session.clear()

review.workspace.list()
review.workspace.clear()
review.status.counts()
review.status.text()
review.status.open()
review.ui.annotations(opts)
review.ui.sessions(opts)
review.ui.workspaces(opts)

review.payload(opts)
review.send(opts)
review.compose(opts)
review.refresh({ checktime = true })
```

Returned annotations are copies rather than mutable internal state.

## Agent workflow

Agents should use the `agent-review` executable rather than raw remote Lua:

```sh
agent-review context
agent-review list
agent-review apply --stdin < findings.json
agent-review refresh
agent-review resolve review-3 review-4
agent-review remove agent-finding-2
```

The executable discovers the Neovim RPC socket through Herdr or tmux, defaults
to the active session, accepts/returns JSON, and runs `checktime` during refresh.
Agent findings for unopened working files are validated and anchored from disk
without opening a window.

The independently versioned RPC boundary remains available to the executable:

```lua
require("agent_review.rpc").dispatch(request)
```

RPC wire schema is v1; persistence schema is v2.

## Current limitations

- Blockwise targets are not implemented.
- Inline old-side column ranges cannot be selected directly.
- Reanchoring requires the selected text itself to remain exact.
- Forge synchronization and offline bundles are deferred.
