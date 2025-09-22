return {
  { "marilari88/neotest-vitest" },
  { "V13Axel/neotest-pest" },
  {
    "nvim-neotest/neotest",
    opts = { adapters = { "neotest-pest", "neotest-vitest" } },
  },
}
