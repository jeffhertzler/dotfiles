local file = assert(vim.env.NATIVE_REVIEW_TEST_FILE)
vim.cmd("edit " .. vim.fn.fnameescape(file))

local bridge = require("agent_bridge").setup({})
local transport = require("agent_bridge.transport")
local original_send = transport.send
local sent
transport.send = function(message, opts, done)
  sent = { message = message, opts = opts }
  if done then done(true) end
end

local review = require("native_review")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local annotation = assert(review.add({ body = "send this" }))
assert(review.send({ submit = true, switch_to_target = false }))
assert(sent and sent.opts.submit and sent.opts.switch_to_target == false)
assert(sent.message:find(annotation.id, 1, true))
assert(sent.message:find("send this", 1, true))
assert(sent.message:find("Neovim RPC server:", 1, true))
transport.send = original_send
