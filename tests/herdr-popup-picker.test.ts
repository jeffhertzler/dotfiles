import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const picker = resolve("dot_local/bin/executable_herdr-popup-picker");

test("lazygit starts in the active pane directory", (t) => {
  const root = mkdtempSync(join(tmpdir(), "herdr-popup-picker-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));

  const workspace = join(root, "workspace");
  const worktree = join(root, "task-worktree");
  const bin = join(root, "bin");
  mkdirSync(workspace);
  mkdirSync(worktree);
  mkdirSync(bin);

  const lazygit = join(bin, "lazygit");
  writeFileSync(lazygit, "#!/usr/bin/env bash\npwd -P\n");
  chmodSync(lazygit, 0o755);

  const result = spawnSync("bash", [picker, "--run", "git"], {
    cwd: workspace,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${bin}${delimiter}${process.env.PATH ?? ""}`,
      HERDR_ACTIVE_PANE_CWD: worktree,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), worktree);
});
