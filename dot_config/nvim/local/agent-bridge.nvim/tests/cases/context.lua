local file = assert(vim.env.AGENT_BRIDGE_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))
local buf = vim.api.nvim_get_current_buf()
local context = require("agent_bridge.context")
local relative = vim.fn.fnamemodify(file, ":~:.")

local payload, err = context.build_file()
assert(payload == "@" .. relative and err == nil)

payload = context.build_file({
  range = 2,
  line1 = 2,
  col1 = 3,
  line2 = 3,
  col2 = 5,
  selection_kind = "char",
})
assert(payload == string.format("%s:L2:C3-L3:C5", relative))

local namespace = vim.api.nvim_create_namespace("AgentBridgeTest")
vim.diagnostic.set(namespace, buf, {
  {
    lnum = 1,
    col = 2,
    end_lnum = 1,
    end_col = 3,
    severity = vim.diagnostic.severity.ERROR,
    message = "broken value",
  },
})

payload, err = context.build_diagnostics({ severity = vim.diagnostic.severity.ERROR })
assert(err == nil)
assert(payload:find("# ERROR Diagnostics", 1, true))
assert(payload:find("## " .. relative, 1, true))
assert(payload:find("Line 2, Col 3: broken value", 1, true))

local missing
missing, err = context.build_diagnostics({ severity = vim.diagnostic.severity.WARN })
assert(missing == nil and err == "no warn diagnostics in current buffer")
vim.diagnostic.reset(namespace, buf)
