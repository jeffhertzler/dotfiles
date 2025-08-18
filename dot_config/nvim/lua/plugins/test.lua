return {
  { "marilari88/neotest-vitest" },
  { "jeffhertzler/neotest-pest" },
  {
    "nvim-neotest/neotest",
    opts = { adapters = { "neotest-pest", "neotest-vitest" } },
  },
}
