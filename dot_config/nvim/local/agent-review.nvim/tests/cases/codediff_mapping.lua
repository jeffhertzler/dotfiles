local adapter = require("agent_review.codediff")
local diff = {
  changes = {
    {
      original = { start_line = 2, end_line = 4 },
      modified = { start_line = 2, end_line = 2 },
    },
    {
      original = { start_line = 5, end_line = 5 },
      modified = { start_line = 3, end_line = 5 },
    },
  },
}

local deleted = assert(adapter.old_line_descriptor(diff, 2, 6))
assert(deleted.row == 1 and deleted.above)
local after_deletion = assert(adapter.old_line_descriptor(diff, 4, 6))
assert(after_deletion.row == 1 and not after_deletion.above)
local after_both = assert(adapter.old_line_descriptor(diff, 6, 6))
assert(after_both.row == 5 and not after_both.above)
