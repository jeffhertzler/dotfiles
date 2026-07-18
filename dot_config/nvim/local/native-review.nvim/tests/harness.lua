local case = assert(vim.env.NATIVE_REVIEW_TEST_CASE, "NATIVE_REVIEW_TEST_CASE is required")
local ok, err = xpcall(function()
  dofile(case)
end, debug.traceback)

if ok then
  print("PASS " .. vim.fs.basename(case))
  vim.cmd("qa!")
else
  io.stderr:write("FAIL " .. vim.fs.basename(case) .. "\n" .. err .. "\n")
  vim.cmd("cquit 1")
end
