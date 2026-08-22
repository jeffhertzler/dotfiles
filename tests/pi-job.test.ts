import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const sourceRoot = fileURLToPath(new URL("..", import.meta.url));
const piJob = join(sourceRoot, "dot_local", "bin", "executable_pi-job");

function executable(path: string, body: string) {
  writeFileSync(path, `#!/usr/bin/env bash\nset -euo pipefail\n${body}`, { mode: 0o755 });
  chmodSync(path, 0o755);
}

function createHarness(t: test.TestContext, continueOnError: boolean) {
  const root = mkdtempSync(join(tmpdir(), "pi-job-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, "home");
  const bin = join(root, "bin");
  const jobs = join(root, "jobs");
  const job = join(jobs, "staged");
  const state = join(root, "state");
  const cwd = join(root, "cwd");
  const log = join(root, "herdr.log");
  mkdirSync(home, { recursive: true });
  mkdirSync(bin, { recursive: true });
  mkdirSync(job, { recursive: true });
  mkdirSync(cwd, { recursive: true });

  executable(
    join(bin, "systemd-analyze"),
    `exit 0\n`,
  );
  executable(
    join(bin, "herdr"),
    `
printf '%q ' "$@" >> "$PI_JOB_TEST_LOG"
printf '\\n' >> "$PI_JOB_TEST_LOG"
args=("$@")
if [[ \${args[0]:-} == --session ]]; then args=("\${args[@]:2}"); fi
case "\${args[0]:-} \${args[1]:-}" in
  "status server") printf '%s\\n' '{"running":true}' ;;
  "workspace list") printf '%s\\n' '{"result":{"workspaces":[]}}' ;;
  "workspace create") printf '%s\\n' '{"result":{"workspace":{"workspace_id":"w1"},"tab":{"tab_id":"w1:t1"},"root_pane":{"pane_id":"w1:p1"}}}' ;;
  "tab rename") printf '%s\\n' '{"result":{"type":"ok"}}' ;;
  "agent start") printf '%s\\n' '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent get") printf '%s\\n' '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent prompt") printf '%s\\n' '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  *) printf 'unexpected fake herdr invocation: %s\\n' "\${args[*]}" >&2; exit 2 ;;
esac
`,
  );
  const external = join(bin, "external-step");
  executable(
    external,
    `
printf 'external stdout; HERDR_ENV=%s; PWD=%s\\n' "\${HERDR_ENV-unset}" "$PWD"
printf 'external stderr\\n' >&2
exit 23
`,
  );

  writeFileSync(join(job, "prompt.md"), "Run phase one.");
  writeFileSync(join(job, "prompt.after.md"), "Run phase two and report.");
  writeFileSync(
    join(job, "job.json"),
    JSON.stringify({
      calendar: "daily",
      cwd,
      topology: "tab",
      workspaceLabel: "Scheduled",
      tabLabel: "staged",
      herdrSession: "default",
      timeoutMs: 60_000,
      steps: [
        { type: "prompt", promptFile: "prompt.md" },
        {
          type: "exec",
          argv: [external],
          timeoutMs: 10_000,
          continueOnError,
        },
        { type: "prompt", promptFile: "prompt.after.md" },
      ],
    }),
  );

  const env = {
    ...process.env,
    HOME: home,
    HERDR_ENV: "1",
    HERDR_PANE_ID: "caller-pane",
    PATH: `${bin}:${process.env.PATH}`,
    PI_JOB_CONFIG_DIR: jobs,
    PI_JOB_STATE_DIR: state,
    PI_JOB_TEST_LOG: log,
    XDG_CONFIG_HOME: join(root, "config"),
  };
  return { env, log };
}

function promptCalls(log: string) {
  return readFileSync(log, "utf8")
    .split("\n")
    .filter((line) => line.includes("agent prompt"));
}

test("runs prompt and external-command steps in one retained agent", (t) => {
  const harness = createHarness(t, true);
  const result = spawnSync("bash", [piJob, "run", "staged"], {
    encoding: "utf8",
    env: harness.env,
  });

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const calls = promptCalls(harness.log);
  assert.equal(calls.length, 2);
  assert.match(calls[0], /Run\\ phase\\ one/);
  assert.match(calls[1], /Run phase two and report/);
  assert.match(calls[1], /External command step 2/);
  assert.match(calls[1], /exit status: 23/);
  assert.match(calls[1], /external stdout/);
  assert.match(calls[1], /HERDR_ENV=unset/);
  assert.match(calls[1], new RegExp(`PWD=\\${join(harness.env.PI_JOB_CONFIG_DIR!, "..", "cwd")}`));
  assert.match(calls[1], /external stderr/);
  assert.match(readFileSync(harness.log, "utf8"), /agent get/);
});

test("stops after a failed external command unless configured to continue", (t) => {
  const harness = createHarness(t, false);
  const result = spawnSync("bash", [piJob, "run", "staged"], {
    encoding: "utf8",
    env: harness.env,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /external command step 2 failed with exit status 23/);
  assert.equal(promptCalls(harness.log).length, 1);
});
