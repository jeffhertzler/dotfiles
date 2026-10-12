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
attaches to the containing block rather than an exact virtual row. Agent Diff's
`<leader>gw` patch workspace materializes staged and unstaged patch rows in a
real buffer; normal `<leader>ra` can therefore target exact deleted, index, and
working lines there.

## Pi feedback

Pi's `/feedback` opens the latest completed reply in a reader tab while Pi keeps
running. It prefers a unique Neovim in the same Herdr tab, then a unique editor
in the same workspace, using the existing Neovim server registry. `NVIM_SERVER`
or an inherited `NVIM` socket explicitly selects an editor. Multiple matches
require an explicit choice; failed or uncertain RPC calls never launch a competing
reader. With no suitable editor, it opens a dedicated reader pane.

Each Pi catalogue owns one reader, so conversations coexist without replacing
code windows or other reader tabs. Replies are fixed, read-only Markdown snapshots. New
replies update the catalogue and winbar indicator, never your text or cursor.
Reading and closing send nothing.

| Key | Reader action |
| --- | --- |
| `<leader>rmb` / `<leader>rmn` | Older / newer reply |
| `<leader>rmp` | Search replies, prompts, titles, and timestamps with full Markdown preview |
| `<leader>rml` | Refresh catalogue and open latest completed reply |
| `<leader>ra` | Add an optional annotation, also in visual mode |
| `<leader>rs` | Stage feedback in the agent's input, focus the agent, and close this feedback view |
| `<leader>rq` | Discard only this reply's annotations and submitted payload |
| `:q` / `<leader>rk` | Save drafts and close the reader view, not the shared editor |

Reader mappings are buffer-local under `<leader>rm`. Standard Vim keys and global
file/project shortcuts remain unchanged.

The picker starts with up to 20 finished replies on the current branch. If none
exists, `/feedback` reports `No completed reply yet` rather than opening progress
text or another branch's reply. An already-open reader remains available for
browsing; its latest-message action leaves the selection unchanged in this case.
`Ctrl-a` in the picker toggles all messages. Drafts survive switching replies, reopening,
and ordinary Neovim quits. Discard never removes a reader's source or metadata.
Submit uses Agent Bridge's existing target selection and staging transport,
just like ordinary review annotations and composer Alt-S. It pastes at the
agent input cursor without clearing existing text or pressing Enter, focuses
the target, then closes only the originating feedback view. Failed or cancelled
staging leaves that view and its drafts available for retry. The normal Neovim
statusline stays under Lualine's control. Reader submission saves annotations but
does not write a `feedback.json` handoff file; that file is only produced by the
legacy standalone flow. Existing saved payloads are left untouched.

A dedicated launcher sets `PI_FEEDBACK_CATALOG` to an absolute schema-version-1
catalogue, then runs `require('agent_review.feedback_reader').open()`. The initial
selection is the latest completed current-branch entry. An empty `latestEntryId`
means there is no such reply. `open({ catalog_path = path, feedback_state_path =
state_path })` can select a specific draft. `NVIM_AGENT_REVIEW_STATE` configures
only the ordinary review store and must not point at a message's annotations;
the dedicated launcher uses a separate `reader-state.json`. Shared editors keep
their environment unchanged.

Each catalogue entry must point to its own direct child directory containing
`source.md` and `metadata.json`; `annotations.json` is created when needed. Metadata must have `reader: true` and matching session/message
identities. Paths must be canonical and may not traverse symlinks; entry IDs are
opaque, not paths. Each open reader polls once per second and updates only
its own windows. It retains the last valid catalogue if a refresh fails and
stops polling when its view closes.

`agent_review.context` is the only storage-selection module. It reads the buffer's
`pi_feedback` metadata and returns an instance containing annotations, sessions,
and persistence. Ordinary code review keeps its original instance. Each feedback
message has an independent instance backed by its own `annotations.json`.
Switching buffers never swaps a global store. Input callbacks capture their
original instance; rendering and debounced saves use the associated instance.

Closing a reader flushes its drafts, disables pending saves, and invalidates
outstanding annotation accepts. Hidden snapshot buffers survive, but cannot
submit or save until reopened. Reopening reuses those buffers and reloads drafts.
If flushing fails, the reader remains protected from catalogue clearing.

### Existing-editor RPC

Restart running Neovim instances after installing this update. Do not hot-reload
Agent Review modules. Both callers and the reader check
`require('agent_review').feedback_context_version == 1`; an older loaded init
module requires a restart even when the new files are already installed.

```lua
require('agent_review.feedback_reader').remote({
  action = 'open', -- 'open', 'focus', or 'status'
  cataloguePath = '/absolute/catalogue.json',
  feedbackStatePath = '/absolute/message/annotations.json', -- optional
})
```

- `open` creates or focuses the catalogue's owned tab. An optional draft path
  selects that message; otherwise an existing reader keeps its selection.
- `focus` targets an existing reader. If its view closed but a failed save left
  drafts protected in memory, it restores that reader's tab for recovery.
- `status` is read-only: no focus, refresh, loading of drafts, or scheduled work.

Success returns `{ ok = true, open = true/false }`, with optional `paneId` and
`socketPath` from `HERDR_PANE_ID` and `HERDR_SOCKET_PATH`. Failure returns
`{ ok = false, error = '...' }`. Results are JSON-serializable Lua tables.
`open = false` means this reader has no timers, pending editors, or saves that
can recreate its catalogue files. A failed final save keeps `open = true` to
prevent clearing. The RPC path never exits Neovim.

The separate `agent-review` CLI/RPC remains scoped to ordinary code reviews,
including ID-based actions and `list --all`. Viewing feedback cannot redirect an
agent's code annotations into a feedback draft. Feedback submission uses its own
reader controls and Agent Bridge staging.

Legacy standalone `feedback.attach()` buffers without `reader: true` retain their
original submit-and-quit and discard-on-quit behavior.

[`FEEDBACK_V2.md`](./FEEDBACK_V2.md) summarizes the implemented reader design.
Combining response and active-session code feedback in one Pi draft remains a
separate plan in [`FEEDBACK_V1_1.md`](./FEEDBACK_V1_1.md).

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

Returned annotations are copies rather than mutable internal state. Calls use
the current buffer's review context by default, including `list({ all = true })`.
ID-based `edit`, `remove`, `resolve`, `reopen`, and `set_status` also accept
`opts.bufnr` for UI callbacks that retain an originating buffer.

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
