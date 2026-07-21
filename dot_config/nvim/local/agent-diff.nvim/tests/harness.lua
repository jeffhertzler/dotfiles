local ok, err = xpcall(function()
  dofile(assert(vim.env.AGENT_DIFF_TEST_CASE))
end, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
