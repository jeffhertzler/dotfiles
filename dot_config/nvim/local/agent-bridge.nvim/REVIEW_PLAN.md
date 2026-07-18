# Native agent review plan

## Status

This document captures the direction established while researching a native
Neovim review workflow for agent-authored changes.

Current setup:

- `agent-bridge.nvim` sends file, selection, and diagnostic context to agents
  through Herdr or tmux.
- Neovim publishes an RPC server address for both Herdr and tmux environments.
- `native-review.nvim` now contains a buffer-first, in-memory annotation spike.
- `codediff.nvim` is installed as an optional diff-view adapter, not as a
  requirement for creating or rendering annotations.
- `review.nvim` was evaluated and removed. Its rendering and CodeDiff lifecycle
  code remain useful references, but its readonly mode, focus behavior, broad
  keymaps, and data model do not fit the desired workflow.
- Hunk will not be embedded in a Neovim terminal because that loses normal
  Neovim editing and navigation.

## Product definition

Build a native Neovim annotation layer where:

- annotations work directly in ordinary editable file buffers;
- diff views add revision and old/new-side context without owning the core;
- deleted content may be rendered virtually without losing old-side identity;
- annotations can target files, hunks, lines, or optional line/column ranges;
- humans and coding agents can both create and manage annotations;
- annotations remain visible while reviewing and editing;
- agent communication uses the existing Herdr/tmux bridge;
- Git is supported first, but the model and UI are not Git-specific;
- JJ and GitHub can be added through adapters without rewriting the review UI.

The annotation model, extmark anchoring, picker, and agent transport must work
without a diff UI. CodeDiff enriches the same annotations with revision-aware
old/new rendering when a diff is open.

```text
ordinary file buffers -----------------------┐
                                             v
Neogit / jj.nvim / Octo -> changeset -> CodeDiff adapter
                                             |
                                             v
                                  native review layer
                                             |
                                             v
                                  agent-bridge + RPC
                                             |
                                             v
                                  Pi / Claude / OpenCode
```

## UX principles

1. **Normal Neovim first**
   - Never make the working file non-modifiable.
   - Do not introduce a separate review mode.
   - Preserve normal motions, text objects, search, registers, LSP, and editing.

2. **Minimal keymaps**
   - Do not override keys such as `i`, `d`, `e`, `q`, `f`, or `<Tab>`.
   - Start with one normal/visual annotation action.
   - Use a picker for list/edit/delete/resolve operations.
   - Leave layout, hunk, and file navigation to whichever diff/VCS adapter is active.

3. **No duplicate permanent sidebars**
   - Neogit, JJ tools, Octo, and CodeDiff can all provide file lists.
   - Only one layer should own changeset/file navigation in a workflow.
   - Prefer `]f`/`[f`, `]n`/`[n`, and Snacks pickers over another permanent panel.
   - CodeDiff's explorer can be hidden when another tool launches the review.

4. **Comments are structured state, not prompt text**
   - Human comments, agent comments, and eventual forge threads use one model.
   - Rendering and transport consume that model independently.

## Buffer-first core

The core owns annotations in regular file buffers using paths, optional
revisions, content anchors, and extmarks. It must support add, render, navigate,
edit, resolve, import, export, and persistence without loading CodeDiff. A
working-file annotation should also appear on the matching working side when a
diff adapter displays that same buffer.

## CodeDiff adapter

Use CodeDiff only for:

- diff computation and alignment;
- inline and side-by-side layouts;
- syntax and character-level highlighting;
- old/new buffer loading;
- hunk and file navigation;
- refreshing after file changes;
- direct file and directory comparisons.

Do not make the review layer depend on CodeDiff's lifecycle, Git explorer, or
repository state. The adapter translates CodeDiff buffers, revisions, diff
ranges, layout changes, and virtual deleted lines into the core model. Removing
CodeDiff must leave regular-buffer annotations fully functional.

## Core technical problem: old-side annotations

Working-buffer annotations use ordinary extmarks and are the baseline. New-side
virtual-revision annotations use the same mechanism when backed by a real
buffer. Old-side and inline-deletion annotations additionally require a
diff-aware anchor.

### Side-by-side layout

The original side is a real readonly/scratch buffer. An annotation can render as
an extmark there while storing the original file path, revision, and line range.

### Inline layout

Deleted lines are CodeDiff `virt_lines`. They do not have independent Neovim
buffer positions, and the cursor cannot enter them. The review layer therefore
needs a mapping such as:

```text
visible deletion block
  -> CodeDiff hunk/change
  -> old file line range
  -> nearest real buffer anchor used only for display
```

Possible initial interaction:

1. Put the cursor beside a deletion block.
2. Invoke the annotation action.
3. If multiple old lines are present, choose an old line/range in a small picker.
4. Optionally narrow the target to columns within the selected old line(s).
5. Store an explicit `side = "old"` annotation.
6. Render its note adjacent to the virtual deletion block.

Toggling inline/side-by-side must preserve the same annotation and only change
its rendering strategy. Column targeting is straightforward in real old/new
buffers and remains optional for virtual deletions, where the renderer must map
the stored old-side columns into CodeDiff's virtual-line chunks.

## Annotation model

Initial model sketch:

```lua
{
  id = "review-123",
  session_id = "session-456",

  author = {
    kind = "human", -- human | agent | forge
    name = "jeff",
  },

  target = {
    file = "lua/example.lua",
    old_file = nil, -- populated for renames
    side = "working", -- working | old | new | file | hunk
    start_line = 42,
    start_col = 8, -- optional
    end_line = 45,
    end_col = 21, -- optional
    column_encoding = "utf-8-byte", -- explicit at persistence/RPC boundaries
    hunk_id = nil,
  },

  body = "This loses the original error context.",
  kind = "issue", -- note | question | suggestion | issue | praise
  status = "open", -- open | acknowledged | resolved | stale

  revision = {
    backend = "git", -- git | jj | files | github
    base_expression = "HEAD",
    base_object_id = "...",
    target_expression = "WORKING",
    target_object_id = nil,
  },

  anchor = {
    before = { "..." },
    selected = { "..." },
    after = { "..." },
    fingerprint = "...",
  },

  remote = nil, -- eventual GitHub thread/review identifiers
  created_at = "...",
  updated_at = "...",
}
```

Line and column numbers are useful location hints, but selected text,
surrounding content, and immutable revision/tree identifiers provide durable
anchoring. A missing column means the whole targeted line range. Characterwise
visual selections populate columns; linewise selections do not. Blockwise
selections can initially normalize to one span per line rather than complicating
the core target shape.

Neovim extmarks use zero-based byte columns with an exclusive end, while the
existing agent-bridge references are human-facing and one-based. Normalize at
API boundaries and record the column encoding explicitly so multibyte text and
future LSP integrations are not ambiguous.

## Reanchoring and freshness

Borrow the conceptual model from `doubt.nvim`:

- `fresh`: target content still matches;
- `reanchored`: target moved but was found from surrounding context;
- `stale`: referenced content changed or cannot be located reliably;
- `resolved`: explicitly completed by a human or agent.

Extmarks should track ordinary edits during a live session. Persisted sessions
must revalidate anchors when reopened or when the agent edits a file. Stale
annotations remain visible but should not silently be sent as current feedback.

## Bidirectional agent protocol

### Human to agent

The review layer builds structured review context and asks `agent-bridge.nvim`
to deliver a concise trigger to the selected Herdr/tmux agent.

Potential public bridge API:

```lua
require("agent_bridge").send_text(payload, {
  submit = true,
  switch_to_target = false,
})
```

Potential actions:

- send all open human annotations;
- send the annotation under the cursor;
- ask the agent to inspect the current review session;
- ask the agent to address annotations and update their statuses.

### Agent to Neovim

Use the Neovim RPC socket already published to Herdr/tmux. Expose batch-oriented
Lua functions or commands:

```lua
require("agent_bridge.review").apply({ comments = { ... } })
```

Protocol operations:

- `review.context`
- `review.list`
- `review.apply` (validated batch add)
- `review.update`
- `review.resolve`
- `review.remove`
- `review.navigate`
- `review.refresh`

RPC targets accept optional `startCol`/`endCol`; omitted columns target complete
lines. The wire format must declare whether end columns are inclusive and which
column encoding is used, then normalize to Neovim's extmark conventions.

Batch application should validate the complete payload before changing state.
Agent-created notes render through the same path as human notes, with distinct
author styling rather than a separate UI.

## Persistence

Requirements:

- survive Neovim restarts;
- support multiple repositories/worktrees and review ranges;
- avoid polluting Git/JJ status;
- be inspectable by an agent when no live RPC session is available;
- use a versioned schema.

Candidate locations:

1. `stdpath("state")` or `stdpath("data")` keyed by repository identity;
2. Git metadata directory for Git-only local state;
3. optional repo-local ignored directory for portable human/agent sessions.

Do not choose a permanent format until the live model and reanchoring proof are
working. Provide import/export so storage can evolve.

## VCS-neutral provider boundary

The review layer should consume a neutral changeset interface:

```lua
---@class ReviewVcsProvider
---@field detect_root fun(path: string): string?
---@field resolve fun(root: string, expression: string): table
---@field changed_files fun(root: string, base: table, target: table): table[]
---@field read_file fun(root: string, revision: table, path: string): string[]?
---@field watch_paths fun(root: string): string[]
```

### Git provider

Support first:

- `HEAD`, branches, tags, hashes, and working tree;
- staged/unstaged state where relevant;
- renames and deleted/untracked files;
- immutable commit/tree identifiers.

### JJ provider

Add later without changing annotations or rendering:

- revsets such as `@`, `@-`, bookmarks, and change IDs;
- working-copy commits and rewritten commits;
- commit/tree IDs plus stable change IDs;
- no staging-area assumptions;
- JJ-native conflicts.

Useful references:

- `NicolasGB/jj.nvim` CodeDiff backend and temporary-file adapter;
- `julienvincent/hunk.nvim` directory-snapshot diff editing;
- `Neojj` for a Neogit-like JJ management model.

## Longer-term native VCS/forge setup

These are integrations, not MVP dependencies:

- **Neogit**: native Git status, staging, commits, branches, rebase, push/pull,
  stashes, and worktrees. It already supports CodeDiff as a viewer.
- **jj.nvim or Neojj**: candidate native JJ management layers.
- **Octo.nvim**: GitHub issues, PRs, comments, and reviews through normal buffers.
- **GitHub adapter**: eventually map local annotations to draft PR comments and
  import existing PR threads into the common model.

Potential origins for a common annotation model:

```text
local human draft
local agent note
GitHub review thread
future GitLab/other forge thread
```

## Reference implementations

Use as inspiration, not mandatory dependencies:

- `esmuellert/codediff.nvim`
  - renderer and lifecycle APIs;
  - inline deleted-line implementation;
  - split/inline toggle and refresh behavior.
- `georgeguimaraes/review.nvim`
  - comment box rendering;
  - popup input;
  - CodeDiff lifecycle hooks;
  - old/new side storage.
  - Avoid its readonly mode, broad keymaps, focus behavior, and simple anchors.
- `makefinks/doubt.nvim`
  - persistent named sessions;
  - reanchoring and stale-state model;
  - agent-written workspace sessions.
- `modem-dev/hunk`
  - session command concepts;
  - batch comment application;
  - agent navigation and review context protocol.
  - Do not embed its TUI.
- `colewhitley/agent-review.nvim`
  - structured review serialization and tmux delivery.
  - Existing agent-bridge transport supersedes its transport.
- `talldan/nvim-diff-review-opencode-plugin`
  - agent control of native Neovim diff views over RPC.

## Phased implementation

### Phase 0: renderer evaluation

Status: substantially complete.

- [x] Install and evaluate CodeDiff.
- [x] Verify inline and side-by-side toggle.
- [x] Verify arbitrary file comparison.
- [x] Identify explorer/sidebar overlap.
- [x] Evaluate review.nvim and reject it as a direct dependency.
- [ ] Continue using CodeDiff long enough to identify refresh/editing edge cases.

### Phase 1: technical spike

Status: in progress in `local/native-review.nvim`.

Goal: prove the annotation core in regular buffers, then enrich it through an
optional CodeDiff adapter.

- [x] Create a small local review module with no persistence.
- [x] Add and render annotations in ordinary file buffers without CodeDiff.
- [x] Share working-file annotations with the matching CodeDiff working side.
- [x] Add one normal/visual annotation action for a line/range.
- [x] Preserve optional columns for characterwise visual selections.
- [x] Render and highlight line-only and line/column targets with extmarks.
- [x] Add an old-side annotation in side-by-side mode, including optional columns.
- [ ] Build the inline virtual-deletion-to-old-line mapping.
- [x] Preserve annotations while toggling layouts.
- [ ] Verify annotations across multi-file CodeDiff selection/refresh.
- [x] Keep the modified buffer editable throughout.
- [x] Add a compact Snacks picker for navigation and removal.
- [x] Remove annotations from the picker, cursor, or public API.
- [x] Edit annotations from the picker, cursor, or public API.

Exit criterion: regular-buffer annotations work independently, and human
annotations on old/working/new diff sides survive layout toggles and ordinary
edits without disrupting CodeDiff or normal Neovim behavior.

### Phase 2: bridge MVP

- [x] Expose a public arbitrary-text send API from agent-bridge.
- [x] Serialize open annotations into a structured payload.
- [x] Send review feedback through existing Herdr/tmux target selection.
- [x] Add RPC `review.list` and atomically validated batch `review.apply` operations.
- [x] Render imported agent annotations with author distinction.
- [x] Add atomically validated RPC resolve/remove/update operations.

Exit criterion: a human can send several annotations to an agent, and the agent
can add several visible annotations back to the same live review.

### Phase 3: durable sessions

- [ ] Versioned persistence format.
- [ ] Repository/worktree/revision session identity.
- [ ] Context fingerprints.
- [ ] Fresh/reanchored/stale validation.
- [ ] Session resume and cleanup.
- [ ] Import/export for offline agent workflows.

### Phase 4: VCS integration

- [ ] Formalize the provider interface.
- [ ] Git provider independent of CodeDiff's explorer.
- [ ] Launch reviews from Neogit selections/events.
- [ ] JJ provider using revsets and `jj file show`/snapshot extraction.
- [ ] Evaluate launching from jj.nvim or Neojj.

### Phase 5: forge integration

- [ ] Import GitHub PR changes and threads.
- [ ] Map local draft comments to GitHub pending review comments.
- [ ] Preserve remote thread IDs and resolution state.
- [ ] Integrate Octo or `gh` without coupling the core model to GitHub.

## Immediate next steps

1. Exercise annotation add/render/navigation in ordinary working buffers.
2. Keep `native-review.nvim` separate from transport and diff integrations.
3. Verify the CodeDiff adapter across multi-file selection and refresh.
4. Inspect CodeDiff's stored diff result and inline renderer to design a stable
   row/old-line mapping.
5. Finish the Phase 1 in-memory proof before designing persistence or adding
   Neogit/JJ/Octo.

## Open questions

- Should review sessions initially live inside agent-bridge or a separate plugin?
- What is the least intrusive interaction for selecting virtual deleted lines
  and, optionally, a column range within them?
- Should persisted/RPC columns use Neovim byte offsets or Unicode codepoints,
  with conversion at the renderer boundary?
- Should annotation kinds be fixed or user-configurable?
- Is a comment thread/reply model needed in the MVP, or are flat annotations
  sufficient until GitHub integration?
- Should agents connect only through Neovim RPC, or should an offline CLI/shared
  file protocol be part of the first durable version?
- When an agent edits annotated code, should a successfully reanchored human
  comment remain open automatically or require explicit resolution?
