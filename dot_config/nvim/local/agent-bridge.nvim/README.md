# agent-bridge.nvim

Private infrastructure and user interface for immediate Neovim-to-agent
communication.

AgentBridge owns:

- Herdr/tmux target discovery and selection;
- message transport;
- freeform composing;
- file, selection, and diagnostic context;
- shared compact/growing text input primitives;
- Neovim RPC socket publication for agent tools.

It does not own persistent review annotations. `agent-review.nvim` depends on
AgentBridge for input, composing, and transport; AgentBridge does not depend on
Agent Review.

## Keymaps

| Mapping | Action |
| --- | --- |
| `<leader>oa` | Compose with current file context |
| visual `<leader>oa` | Compose with selected context |
| `<leader>oA` | Stage current context directly |
| visual `<leader>oA` | Stage selected context directly |
| `<leader>or` | Resume the hidden composer |
| `<leader>ot` | Select/pin an agent target |
| `<leader>oT` | Clear the pinned target |

## Command

```vim
:Agent compose [file|buffers|diagnostics|errors]
:Agent send [file|buffers|diagnostics|errors]
:Agent resume
:Agent target [select|clear]
```

`:Agent` defaults to `:Agent compose file`.

## Lua API

```lua
local agent = require("agent_bridge")

agent.send(message, opts, callback)
agent.compose(initial_message)
agent.context.send(kind, opts)
agent.context.compose(kind, opts)
agent.context.send_visual()
agent.context.compose_visual()
agent.prompt.resume()
agent.target.select()
agent.target.clear()
```

`send` is the raw transport boundary used by Agent Review. Supported options
include `submit`, `switch_to_target`, and `interactive_prompt`.

## Shared input

```lua
local input = require("agent_bridge.input").new({
  title = " Comment ",
  min_height = 1,
  max_height = 8,
  persistent = false,
  on_accept = function(text, action, done)
    done(true)
  end,
})
input:open("initial text")
```

Inputs are bordered native Markdown buffers that open in insert mode, grow with
content, and retain normal Neovim editing. AgentBridge's composer uses a larger
persistent instance; Agent Review uses compact transient instances.
