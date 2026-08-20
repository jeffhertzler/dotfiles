# Agent-to-human attention hooks

_Researched 2026-08-18 against the installed tools and primary sources._

## Practical conclusion

There is **not one hook/event schema shared by the major terminal agents**. Claude Code, Codex, OpenCode, and Pi each expose different product APIs, and Moshi and Herdr therefore maintain per-agent adapters.

There are, however, two real interoperable protocols worth reusing rather than inventing another wire format:

- **ACP v2** is the closest match for an agent/host contract: baseline `session/request_permission`, optional `elicitation/create`, and `session/update` state transitions to `requires_action` while blocked and `running` when resumed. OpenCode officially runs as an ACP agent via `opencode acp`; the examined Claude Code, Codex CLI, and Pi surfaces do not expose ACP natively. ([ACP overview](https://agentclientprotocol.com/protocol/v2/overview), [permission request](https://agentclientprotocol.com/protocol/v2/tool-calls#requesting-permission), [prompt lifecycle](https://agentclientprotocol.com/protocol/v2/prompt-lifecycle), [OpenCode ACP](https://opencode.ai/docs/acp/))
- **MCP elicitation** standardizes an _MCP server_ asking for structured user input through an MCP client (`elicitation/create`, capability negotiation, `accept | decline | cancel`). It is not a general coding-agent permission or “agent needs attention” lifecycle. ([MCP 2025-11-25 elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation))

For Pi specifically, a usable implementation already exists: [`pi-ask-user`](https://github.com/edlsh/pi-ask-user/tree/2de7e145227f7a527e995e323a50e7ee9bf88b0e) v0.14.0 registers a sequential `ask_user` tool and brackets its wait with `herdr:blocked {active:true,...}` / `{active:false}`. The installed Herdr Pi integration consumes exactly that event. This is effective today, but `herdr:blocked` is a **Pi event-bus convention coupled to Herdr**, not an interoperable standard.

## What the agents expose

| Agent | Native human-input surface | Classification |
|---|---|---|
| **Claude Code 2.1.220** | `PermissionRequest`; `AskUserQuestion` as a tool visible to `PreToolUse`/`PostToolUse`; `Notification` matcher values including `permission_prompt`, `elicitation_dialog`, and `agent_needs_input`; separate `Elicitation`/`ElicitationResult` for MCP. The Agent SDK unifies permissions and `AskUserQuestion` through `canUseTool`. ([hooks](https://code.claude.com/docs/en/hooks), [SDK user input](https://code.claude.com/docs/en/agent-sdk/user-input)) | Rich, but Anthropic-specific. |
| **Codex CLI 0.146.1** | CLI hooks include `PermissionRequest`, which can allow, deny, or decline to decide and leave the normal prompt in place. The separate Codex app-server protocol has server requests `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, experimental `item/tool/requestUserInput`, `item/permissions/requestApproval`, and `mcpServer/elicitation/request`. ([hooks](https://developers.openai.com/codex/hooks#permissionrequest), [app server](https://developers.openai.com/codex/app-server)) | Rich, but OpenAI-specific; the hooks surface is narrower than app-server. |
| **OpenCode 1.18.15** | Event stream has `permission.asked`/`permission.replied` and `question.asked`/`question.replied`/`question.rejected`; corresponding APIs resolve the pending request. It also officially implements ACP. ([plugin events](https://opencode.ai/docs/plugins/#events), [current event types](https://github.com/anomalyco/opencode/blob/ec3ae17e/packages/sdk/js/src/v2/gen/types.gen.ts), [ACP](https://opencode.ai/docs/acp/)) | Product events plus an interoperable ACP transport. |
| **Pi 0.84.2** | Core extension API supplies blocking `ctx.ui.select/confirm/input/editor` calls and a blockable `tool_call` event. RPC mode translates dialogs into correlated `extension_ui_request` / `extension_ui_response` messages. Pi ships `question.ts` and `permission-gate.ts` examples, not a built-in model-facing question tool or core `input_required` lifecycle event. ([extensions](https://github.com/earendil-works/pi/blob/v0.84.2/packages/coding-agent/docs/extensions.md), [RPC UI protocol](https://github.com/earendil-works/pi/blob/v0.84.2/packages/coding-agent/docs/rpc.md#extension-ui-protocol), [question example](https://github.com/earendil-works/pi/blob/v0.84.2/packages/coding-agent/examples/extensions/question.ts), [permission example](https://github.com/earendil-works/pi/blob/v0.84.2/packages/coding-agent/examples/extensions/permission-gate.ts)) | Generic inside Pi, but Pi-specific and missing a host-visible wait lifecycle in core. |

The installed Pi package sources inspected for this row are under `/home/jeffhertzler/.local/share/mise/installs/npm-earendil-works-pi-coding-agent/0.84.2/node_modules/.mise/@earendil-works+pi-coding-agent@0.84.2/node_modules/@earendil-works/pi-coding-agent/{docs,examples}`.

ACP permission and elicitation are deliberately separate concepts. MCP elicitation is narrower still: its capability says the client can collect information for an MCP server; it does not imply that the host can observe every model question, sandbox escalation, plan approval, or terminal prompt.

## Moshi: normalization and exact installed mappings

Official Moshi docs say `moshi-hook` normalizes agent-specific hooks into `approval_required`, `task_complete`, `session_started`, `tool_running`, and `tool_finished`; `approval_required` means permission **or** a user answer. The daemon owns the Unix-socket/WebSocket approval round trip. Its supported matrix includes Claude Code, Codex, OpenCode, Pi, Antigravity, Cursor, Kimi, Qwen, Grok, OMP, and Hermes. ([Moshi hooks](https://getmoshi.app/docs/hooks))

The installed binary is **moshi-hook 0.2.86**, module `github.com/rjyo/moshi/app-hook`, commit `b0551676ef899065b910bf15531ed9915140ab61`, built 2026-08-18. `moshi-hook status --json` reports the four adapters below as `current`.

| Adapter | Exact installed source events/hooks | Human-input behavior |
|---|---|---|
| **Claude Code** | `PermissionRequest` (synchronous); `PreToolUse` and `PostToolUse` matched to `AskUserQuestion` and `ExitPlanMode`; plus `SessionStart`, `UserPromptSubmit`, `Stop`, `SessionEnd`. | Permission is a true approve/deny round trip. Question/plan hooks surface the waiting lifecycle; open-ended questions are answered in the terminal rather than fabricated as approvals. |
| **Codex** | `PermissionRequest`, `SessionStart`, `UserPromptSubmit`, `Stop`. | Permission is a true approve/deny round trip. The generated CLI-hook registration has no explicit `requestUserInput` event; Codex app-server’s richer question RPC is a different integration surface. |
| **OpenCode** | `chat.message`; `session.created/status/idle/deleted/error`; `permission.asked/updated/replied`; `question.asked/replied/rejected`; `permission.ask`; tool before/after hooks and message updates for activity/title tracking. | `permission.ask` and permission events submit Moshi approve/deny decisions back through the OpenCode client. `question.asked` becomes `approval_required` with **“Answer in terminal”**; replies/rejections clear/update it. |
| **Pi** | `session_start` → `SessionStart`; `before_agent_start` → `UserPromptSubmit`; `agent_start` → `AgentStart`; `agent_settled` → `AgentEnd`; `session_shutdown` → `SessionEnd`. | Completion/session tracking only. It does **not** observe `ctx.ui` dialogs, `tool_call` approval waits, `herdr:blocked`, or a generic question lifecycle, so current Moshi Pi support does not provide generic question/approval attention. |

Primary installed artifacts: `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.config/opencode/plugins/moshi-hooks.ts`, and `~/.pi/agent/extensions/moshi-hooks.ts`; helper binary `~/.local/bin/moshi-hook`. The generated OpenCode and Pi files are readable and are the basis for the exact mapping above. This is more precise than treating Moshi’s normalized categories as an agent-side standard: they are Moshi’s own adapter schema.

## Herdr: state projection, not a universal approval transport

Herdr’s public contract is a small semantic projection: integrations report `working`, `blocked`, or `idle` through `pane.report_agent`; `blocked` means the agent needs a user decision. Herdr explicitly divides integrations into **lifecycle authorities** and **session-identity-only** adapters, falling back to process/screen detection where hook coverage is incomplete. ([integrations](https://herdr.dev/docs/integrations/), [agent authority model](https://herdr.dev/docs/agents/))

Installed **Herdr 0.8.0** exactly matches the v0.8.0 bundled integration sources:

| Adapter | Exact mapping in Herdr 0.8.0 |
|---|---|
| **Pi integration v8** | TUI `session_start` reports session identity/current state; `agent_start` → `working`; `agent_settled` while truly idle → `idle`; shared Pi event `herdr:blocked active:true` → `blocked` (with label), `active:false` → previous `working`/`idle`. ([source](https://github.com/herdrdev/herdr/blob/v0.8.0/src/integration/assets/pi/herdr-agent-state.ts)) |
| **OpenCode integration v9** | `chat.message` → `working`; `session.status` maps `idle` → `idle` and active/busy/pending/retry/running/streaming/working → `working`; `tool.execute.before/after`, permission/question replies, and compaction → `working`; `permission.asked`, `question.asked`, and `session.error` → `blocked`; `session.idle` → `idle`. It separately reports session identity and filters child-session cross-talk. ([source](https://github.com/herdrdev/herdr/blob/v0.8.0/src/integration/assets/opencode/herdr-agent-state.js)) |
| **Claude integration v7** | Only `SessionStart` → native session identity. `working`/`blocked`/`idle` continue to come from Herdr’s screen manifest, which recognizes visible question and permission UI. ([source](https://github.com/herdrdev/herdr/blob/v0.8.0/src/integration/assets/claude/herdr-agent-state.sh)) |
| **Codex integration v7** | Only `SessionStart` → native session identity. State, including blocked approval/question UI, comes from screen detection. ([source](https://github.com/herdrdev/herdr/blob/v0.8.0/src/integration/assets/codex/herdr-agent-state.sh)) |

Local installed paths are `~/.pi/agent/extensions/herdr-agent-state.ts`, `~/.config/opencode/plugins/herdr-agent-state.js`, `~/.claude/hooks/herdr-agent-state.sh`, and `~/.codex/herdr-agent-state.sh`; byte comparison confirms each matches the cited v0.8.0 source. Herdr can focus/attach to or send input to a blocked pane, but these state reports are not themselves a structured approval/question response protocol.

## Pi extension answer

Pi core provides the primitives, and its shipped `question.ts` proves a model-facing tool can block on custom UI, but core does not publish “wait opened/resolved.” [`pi-ask-user` v0.14.0](https://www.npmjs.com/package/pi-ask-user) fills both gaps:

1. `ask_user` is `executionMode: "sequential"`, preventing sibling side-effecting tools from running while the question waits.
2. It emits `herdr:blocked` before either free-form input or option UI and clears it in `finally` on answer, cancellation, timeout, or error. ([exact source](https://github.com/edlsh/pi-ask-user/blob/2de7e145227f7a527e995e323a50e7ee9bf88b0e/index.ts#L1991-L2255))
3. Herdr’s installed Pi adapter consumes that event directly.

So the practical answer is **yes for ask-user + Herdr attention**, **no for a generic cross-host Pi attention standard**, and **no for Moshi Pi attention without another bridge**. If a new neutral Pi lifecycle is introduced, it should represent request identity, kind (`question | permission | elicitation`), open/resolved/cancelled state, display data, and response ownership; adapters could then project it to ACP `requires_action`, Moshi `approval_required`, and Herdr `blocked` without naming any one host in the core event.
