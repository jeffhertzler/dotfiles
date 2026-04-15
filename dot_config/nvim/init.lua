--
--          _|  _|    _|
--          _|  _|    _|      Jeff Hertzler
--          _|  _|_|_|_|      https://github.com/jeffhertzler
--    _|    _|  _|    _|      http://jeffhertzler.com
--      _|_|    _|    _|
--

require("config.lazy")
require("config.agent_bridge").setup({
  tmux = {
    process_name = { "pi", "opencode", "cursor-agent", "claude" },
  },
  prompt = {
    width_ratio = 0.5,
    height_ratio = 0.28,
    title = " Compose to Agent ",
  },
})
