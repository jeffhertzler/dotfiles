local file = assert(vim.env.AGENT_BRIDGE_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))

local transport = require("agent_bridge.transport")
local original_send = transport.send
local sent = {}
transport.send = function(message, opts, done)
  table.insert(sent, { message = message, opts = opts })
  if done then done(true) end
end

local bridge = require("agent_bridge").setup({})
assert(vim.fn.exists(":Agent") == 2)
assert(vim.fn.exists(":AgentBridge") == 0)

local completed
assert(bridge.send("direct message", { submit = true }, function(ok) completed = ok end))
assert(completed == true)
assert(sent[1].message == "direct message" and sent[1].opts.submit == true)

completed = nil
assert(not bridge.send("  ", {}, function(ok) completed = ok end))
assert(completed == false and #sent == 1)

assert(bridge.context.send("file", { switch_to_target = false }))
assert(sent[2].message == "@" .. vim.fn.fnamemodify(file, ":~:."))
assert(sent[2].opts.switch_to_target == false)

vim.cmd("Agent send file")
assert(sent[3].message == sent[2].message)

transport.send = original_send
