import assert from "node:assert/strict";
import { ChildProcess, spawn } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const sourceRoot = fileURLToPath(new URL("..", import.meta.url));
const supervisor = join(sourceRoot, "dot_local", "bin", "executable_herdr-service-supervisor");
const unit = join(sourceRoot, "dot_config", "private_systemd", "private_user", "herdr.service");

function processExists(pid: number) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitFor(predicate: () => boolean, message: string, timeoutMs = 3000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.fail(message);
}

function createHarness(t: test.TestContext, initiallyRunning = false) {
  const root = mkdtempSync(join(tmpdir(), "herdr-supervisor-test-"));
  const fakeHerdr = join(root, "herdr");
  const eventLog = join(root, "events.log");
  if (initiallyRunning) writeFileSync(join(root, "running"), "");
  mkdirSync(root, { recursive: true });
  writeFileSync(
    fakeHerdr,
    `#!/usr/bin/env bash
set -u
root=$FAKE_HERDR_ROOT
printf '%s\n' "$*" >> "$root/invocations.log"
args=("$@")
if [[ \${args[0]:-} == --session ]]; then args=("\${args[@]:2}"); fi
case "\${args[0]:-} \${args[1]:-}" in
  "status server")
    if [[ -e $root/running ]]; then printf '{"running":true}\n'; else printf '{"running":false}\n'; fi
    exit 0
    ;;
  "server stop")
    printf 'stop\n' >> "$root/events.log"
    touch "$root/stop"
    rm -f "$root/running"
    exit 0
    ;;
  "server ")
    printf 'start %s\n' "$$" >> "$root/events.log"
    printf '%s\n' "$$" > "$root/direct.pid"
    touch "$root/running"
    sleep 1000 &
    pane=$!
    printf '%s\n' "$pane" > "$root/pane.pid"
    trap 'rm -f "$root/running"; kill "$pane" 2>/dev/null || true; exit 0' TERM INT
    while [[ ! -e $root/stop ]]; do
      if [[ -e $root/handoff ]]; then
        rm -f "$root/handoff"
        "$0" replacement &
        printf '%s\n' "$!" > "$root/replacement.pid"
        exit 0
      fi
      sleep 0.02
    done
    rm -f "$root/running"
    kill "$pane" 2>/dev/null || true
    exit 0
    ;;
  "replacement ")
    printf 'replacement %s\n' "$$" >> "$root/events.log"
    touch "$root/running"
    trap 'rm -f "$root/running"; exit 0' TERM INT
    while [[ ! -e $root/stop ]]; do sleep 0.02; done
    rm -f "$root/running"
    exit 0
    ;;
  *) exit 2 ;;
esac
`,
    { mode: 0o755 },
  );
  chmodSync(fakeHerdr, 0o755);

  const env = {
    ...process.env,
    FAKE_HERDR_ROOT: root,
    HERDR_BIN: fakeHerdr,
    HERDR_SUPERVISOR_HANDOFF_POLLS: "8",
    HERDR_SUPERVISOR_POLL_SECONDS: "0.02",
    HERDR_SUPERVISOR_POST_CHILD_POLLS: "3",
    HERDR_SUPERVISOR_STARTUP_POLLS: "5",
  };
  const child = spawn("bash", [supervisor], { env, stdio: "ignore" });
  t.after(async () => {
    if (child.exitCode === null) {
      const exited = waitForExit(child);
      child.kill("SIGTERM");
      await Promise.race([
        exited,
        new Promise((resolve) => setTimeout(resolve, 1000)),
      ]);
      if (child.exitCode === null) child.kill("SIGKILL");
    }
    for (const file of ["direct.pid", "replacement.pid", "pane.pid"]) {
      const path = join(root, file);
      if (!existsSync(path)) continue;
      const pid = Number(readFileSync(path, "utf8").trim());
      if (Number.isInteger(pid) && processExists(pid)) {
        try { process.kill(pid, "SIGKILL"); } catch {}
      }
    }
    rmSync(root, { recursive: true, force: true });
  });
  return { child, eventLog, root, stderr: () => "" };
}

function waitForExit(child: ChildProcess) {
  return new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((resolve) => {
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });
}

test("starts Herdr when status returns running false with exit zero", async (t) => {
  const harness = createHarness(t);
  await waitFor(() => existsSync(join(harness.root, "direct.pid")), "supervisor did not start Herdr");
  const events = readFileSync(harness.eventLog, "utf8");
  assert.equal(events.match(/^start /gm)?.length, 1);
  assert.equal(harness.child.exitCode, null, harness.stderr());
});

test("adopts a running server without starting a competitor", async (t) => {
  const harness = createHarness(t, true);
  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.equal(existsSync(harness.eventLog), false);
  assert.equal(harness.child.exitCode, null, harness.stderr());
});

test("keeps its stable process and pane alive across a server handoff", async (t) => {
  const harness = createHarness(t);
  await waitFor(() => existsSync(join(harness.root, "pane.pid")), "fake pane did not start");
  const supervisorPid = harness.child.pid!;
  const panePid = Number(readFileSync(join(harness.root, "pane.pid"), "utf8").trim());
  writeFileSync(join(harness.root, "handoff"), "");
  await waitFor(() => existsSync(join(harness.root, "replacement.pid")), "replacement did not start");
  const replacementPid = Number(readFileSync(join(harness.root, "replacement.pid"), "utf8").trim());
  await new Promise((resolve) => setTimeout(resolve, 150));

  assert.equal(processExists(supervisorPid), true);
  assert.equal(processExists(panePid), true);
  assert.equal(processExists(replacementPid), true);
  const events = readFileSync(harness.eventLog, "utf8");
  assert.equal(events.match(/^start /gm)?.length, 1);
  assert.equal(events.match(/^replacement /gm)?.length, 1);
});

test("exits nonzero after permanent loss of an adopted server", async (t) => {
  const harness = createHarness(t, true);
  await new Promise((resolve) => setTimeout(resolve, 80));
  rmSync(join(harness.root, "running"));
  const result = await waitForExit(harness.child);
  assert.equal(result.code, 1, harness.stderr());
});

test("stops the current Herdr server when systemd terminates the supervisor", async (t) => {
  const harness = createHarness(t);
  await waitFor(() => existsSync(join(harness.root, "direct.pid")), "fake server did not start");
  const exited = waitForExit(harness.child);
  harness.child.kill("SIGTERM");
  const result = await exited;
  assert.equal(result.code, 0, harness.stderr());
  const events = readFileSync(harness.eventLog, "utf8");
  assert.equal(events.match(/^stop$/gm)?.length, 1);
});

test("the systemd unit keeps a stable supervisor main process", () => {
  const text = readFileSync(unit, "utf8");
  assert.match(text, /^ExecStart=%h\/\.local\/bin\/herdr-service-supervisor$/m);
  assert.match(text, /^Restart=on-failure$/m);
  assert.match(text, /^KillMode=mixed$/m);
  assert.doesNotMatch(text, /^ExecStart=.*herdr .* server$/m);
  assert.doesNotMatch(text, /^KillMode=(process|none)$/m);
});
