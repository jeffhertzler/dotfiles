import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("gaming Flatpak NVIDIA maintenance (isolated, no live state)", () => {
  const result = spawnSync("/usr/bin/python3", ["-I", fileURLToPath(new URL("./flatpak-nvidia-sync_test.py", import.meta.url))], {
    encoding: "utf8",
    timeout: 30_000,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stdout + result.stderr);
});
