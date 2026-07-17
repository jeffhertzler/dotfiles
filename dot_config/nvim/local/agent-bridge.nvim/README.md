# agent-bridge.nvim

Private Neovim plugin for composing and sending file, selection, and diagnostic
context to coding agents.

- Uses Herdr's agent APIs inside Herdr and tmux pane APIs elsewhere.
- Stages multiline Herdr messages with bracketed paste.
- Selects Herdr agents from the current workspace and prefers the current tab.
- Selects configured agent processes from the current tmux window.
- Keeps target selection stateless unless explicitly pinned on either backend.

Configuration and keymaps live in
`~/.config/nvim/lua/plugins/agent-bridge.lua`.

## Commands

- `:AgentBridge[Interactive]`
- `:AgentBridgeAll[Interactive]`
- `:AgentBridgeDiagnostics[All]`
- `:AgentBridgeDiagnosticsErrors[All]`
- `:AgentBridgeResume`
- `:AgentBridgeTarget`
- `:AgentBridgeTargetClear`
