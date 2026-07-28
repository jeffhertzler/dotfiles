#!/usr/bin/env node

import { spawnSync } from "node:child_process";

const direction = process.argv[2];
const keys = {
  left: "ctrl+h",
  down: "ctrl+j",
  up: "ctrl+k",
  right: "ctrl+l",
};

if (!Object.hasOwn(keys, direction)) {
  throw new Error("usage: herdr-navigate.mjs left|down|up|right");
}

const paneId = process.env.HERDR_ACTIVE_PANE_ID || process.env.HERDR_PANE_ID;
const herdr = process.env.HERDR_BIN_PATH || "herdr";

if (!paneId) {
  throw new Error("HERDR_ACTIVE_PANE_ID is unavailable");
}

function run(args, { allowFailure = false } = {}) {
  const result = spawnSync(herdr, args, {
    encoding: "utf8",
    windowsHide: true,
  });

  if (result.error) throw result.error;
  if (!allowFailure && result.status !== 0) {
    throw new Error(result.stderr.trim() || `herdr ${args.join(" ")} failed`);
  }

  return result;
}

function foregroundIsNeovim() {
  const result = run(["pane", "process-info", "--pane", paneId], { allowFailure: true });
  if (result.status !== 0) return false;

  try {
    const response = JSON.parse(result.stdout);
    const processes = response.result?.process_info?.foreground_processes || [];
    return processes.some(({ name = "" }) => /^(?:g?vim|nvim|view)(?:diff)?(?:\.exe)?$/i.test(name));
  } catch {
    return false;
  }
}

if (foregroundIsNeovim()) {
  run(["pane", "send-keys", paneId, keys[direction]]);
} else {
  run(["pane", "focus", "--direction", direction, "--pane", paneId]);
}
