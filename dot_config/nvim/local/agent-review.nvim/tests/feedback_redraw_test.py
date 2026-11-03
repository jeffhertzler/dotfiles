"""Paint feedback in an embedded UI; headless-only tests miss EOF redraw bugs."""
import os
from pathlib import Path
import sys

import pynvim

plugin = Path(sys.argv[1]).resolve()
root = Path(sys.argv[2]).resolve()
root.mkdir(parents=True, exist_ok=True)
os.environ["AGENT_REVIEW_PLUGIN_ROOT"] = str(plugin)
os.environ["NVIM_AGENT_REVIEW_STATE"] = str(root / "ordinary-state.json")
# Never register this test editor as a live user target.
for key in list(os.environ):
    if key.startswith("HERDR_") or key in ("NVIM", "NVIM_LISTEN_ADDRESS"):
        os.environ.pop(key, None)

editor = pynvim.attach("child", argv=[
    os.environ.get("NVIM_TEST_PROG", "nvim"), "--embed", "-i", "NONE",
    "-u", str(plugin / "tests/minimal_init.lua"),
])
try:
    editor.ui_attach(160, 48, rgb=True, ext_linegrid=True)
    result = editor.exec_lua(r"""
        local root = ...
        local reply = root .. '/reply'
        vim.fn.mkdir(reply, 'p')
        local lines = {}
        for i = 1, 29 do lines[i] = 'sample line ' .. i end
        vim.fn.writefile(lines, reply .. '/source.md')
        local function json(path, value) vim.fn.writefile({vim.json.encode(value)}, path) end
        json(reply .. '/metadata.json', {
            schemaVersion=1, reader=true, piSessionId='screen-test', assistantMessageId='reply',
            feedbackDirectory=reply, sourcePath=reply .. '/source.md', feedbackPath=reply .. '/feedback.json',
        })
        local catalogue = root .. '/catalogue.json'
        json(catalogue, {
            schemaVersion=1, piSessionId='screen-test', latestEntryId='reply', messages={{
                entryId='reply', title='EOF feedback', prompt='Question', timestamp='now', onBranch=true, finished=true,
                sourcePath=reply .. '/source.md', metadataPath=reply .. '/metadata.json', feedbackStatePath=reply .. '/annotations.json',
            }},
        })
        vim.o.wrap = true
        vim.o.linebreak = true
        vim.o.conceallevel = 2
        -- A Markdown highlighter normally supplies these conceal marks. One
        -- mark anywhere in the buffer is enough; no UI plugin is required.
        local ns = vim.api.nvim_create_namespace('feedback_screen_conceal')
        vim.api.nvim_create_autocmd('FileType', {pattern='markdown', callback=function(event)
            vim.api.nvim_buf_set_extmark(event.buf, ns, 2, 0, {end_col=3, conceal=''})
        end})
        local reader = require('agent_review.feedback_reader')
        local request = {action='open', cataloguePath=catalogue}
        local opened = reader.remote(request)
        assert(opened.ok, opened.error)
        vim.api.nvim_win_set_cursor(0, {29, 0})
        -- Seed the saved draft without triggering the bug before the open seam.
        vim.wo.linebreak = false
        assert(require('agent_review').annotation.add({body='Feedback on the final line'}))
        assert(require('agent_review.persistence').save_now())
        reader.close_view()
        -- Reopen the persisted EOF comment through the real /feedback path.
        local reopened = reader.remote(request)
        if not reopened.ok then return reopened end
        vim.cmd('redrawstatus')
        vim.cmd('redraw!')
        assert(vim.api.nvim_buf_line_count(0) == 29)
        assert(vim.wo.wrap, 'feedback must still wrap')
        assert(vim.wo.conceallevel == 2, 'feedback must retain Markdown conceal')
        assert(#require('agent_review').annotation.list() == 1)
        return reopened
    """, str(root))
    assert result["ok"], result.get("error", result)
    for _ in range(5):
        editor.command("redrawstatus")
        editor.command("redraw!")
    errmsg = editor.eval("v:errmsg")
    assert "E315" not in errmsg, errmsg
    print("PASS feedback_redraw_test.py")
finally:
    try:
        editor.command("qa!")
    except (EOFError, OSError):
        pass
