return {
  "blink.cmp",
  opts = {
    completion = {
      trigger = {
        show_on_insert_on_trigger_character = false,
      },
    },
    keymap = {
      ["<C-k>"] = { "select_prev", "fallback" },
      ["<C-j>"] = { "select_next", "fallback" },
    },
  },
}
