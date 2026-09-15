import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { sweepSubagentRetention } from "../dot_pi/agent/extensions/herdr-subagent/retention.ts";

const DAY = 86_400_000;
const NOW = Date.UTC(2026, 5, 1);
const ID = "11111111-1111-4111-8111-111111111111";
const PARENT = "parent-session-1";

type Json = Record<string, any>;

function fixture(t: { after: (fn: () => void) => void }) {
  const root = mkdtempSync(join(tmpdir(), "subagent-retention-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const artifactRoot = join(root, "artifacts");
  const sessionRoot = join(root, "sessions");
  const directory = join(artifactRoot, ID);
  const folder = join(sessionRoot, "--project--");
  mkdirSync(directory, { recursive: true });
  mkdirSync(folder, { recursive: true });
  const manifestFile = join(directory, "task.json");
  const resultFile = join(directory, "result.json");
  const stateFile = join(directory, "state.json");
  const parentFile = join(folder, `2026-01-01_${PARENT}.jsonl`);
  const childFile = join(folder, `2026-01-02_${ID}.jsonl`);
  const header = { type: "session", version: 3, id: PARENT, cwd: "/project" };
  const owner = { type: "message", id: "owner", parentId: null, message: { role: "user", content: "Delegate" } };
  const ack = { type: "custom_message", id: "ack", parentId: "owner", customType: "subagent_result", content: "Done", details: { id: ID, status: "completed" } };
  const writeParent = (entries: Json[] = [owner, ack], first: Json = header) =>
    writeFileSync(parentFile, [first, ...entries].map((entry) => JSON.stringify(entry)).join("\n") + "\n");
  const manifest: Json = {
    schemaVersion: 1, id: ID, agentSessionId: ID, parentSessionId: PARENT,
    parentEntryId: "owner", parentSessionFile: parentFile, cleaned: true,
    status: "completed", delivered: true, resultDirectory: directory,
    resultFile, stateFile, extra: { preserved: "yes" },
  };
  const save = (patch: Json = {}) => writeFileSync(manifestFile, JSON.stringify({ ...manifest, ...patch }));
  const load = () => JSON.parse(readFileSync(manifestFile, "utf8"));
  const age = (file: string, days = 60) => utimesSync(file, new Date(NOW - days * DAY), new Date(NOW - days * DAY));
  save();
  writeParent();
  writeFileSync(childFile, JSON.stringify({ ...header, id: ID }) + "\n");
  writeFileSync(resultFile, JSON.stringify({ output: "Done" }));
  writeFileSync(stateFile, "{}");
  for (const file of [manifestFile, resultFile, stateFile, childFile]) age(file);
  const sweep = (overrides: Partial<Parameters<typeof sweepSubagentRetention>[0]> = {}) =>
    sweepSubagentRetention({ artifactRoot, sessionRoot, retentionDays: 30, now: NOW, ...overrides });
  return { root, artifactRoot, sessionRoot, directory, folder, manifestFile, resultFile, stateFile,
    parentFile, childFile, manifest, header, owner, ack, writeParent, save, load, age, sweep };
}

test("first observed persisted acknowledgement starts retention without trusting old manifest mtime", (t) => {
  const f = fixture(t);
  const outcome = f.sweep();
  assert.deepEqual(outcome, { eligible: [ID], expired: [], warnings: [] });
  assert.deepEqual(f.load(), { ...f.manifest, retentionEligibleAt: NOW });
  assert.equal(statSync(f.manifestFile).mode & 0o777, 0o600);
  assert.equal(readFileSync(f.resultFile, "utf8"), '{"output":"Done"}');
  assert.ok(statSync(f.childFile).isFile());
});

test("expires at the 30-day boundary and retains the receipt, parent, and unrelated histories", (t) => {
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 30 * DAY });
  const parentBefore = readFileSync(f.parentFile);
  const unrelated = join(f.folder, `2025-01-01_${ID}-other.jsonl`);
  writeFileSync(unrelated, "legacy history without a receipt");
  const extra = join(f.directory, "notes.txt");
  writeFileSync(extra, "keep");
  assert.deepEqual(f.sweep({ now: NOW - 1 }), { eligible: [ID], expired: [], warnings: [] });
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  assert.deepEqual(f.load(), { ...f.manifest, retentionEligibleAt: NOW - 30 * DAY, expiredAt: NOW });
  for (const file of [f.resultFile, f.stateFile, f.childFile]) {
    assert.throws(() => statSync(file), { code: "ENOENT" });
  }
  assert.deepEqual(readFileSync(f.parentFile), parentBefore);
  assert.equal(readFileSync(unrelated, "utf8"), "legacy history without a receipt");
  assert.equal(readFileSync(extra, "utf8"), "keep");
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [], warnings: [] });
});

test("a queued result and delivered flag are not a persisted acknowledgement", (t) => {
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY });
  f.writeParent([f.owner]);
  const before = readFileSync(f.manifestFile);
  assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
  assert.deepEqual(readFileSync(f.manifestFile), before);
  assert.ok(existsSync(f.resultFile));
  assert.ok(existsSync(f.childFile));
});

for (const content of [undefined, "", "  ", [], [{ type: "text", text: "" }]]) {
  test(`does not collect a Task from an empty report: ${JSON.stringify(content)}`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY });
    f.writeParent([f.owner, { ...f.ack, content }]);
    assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
    f.writeParent([f.owner, {
      type: "message", id: "wait", parentId: "owner", message: {
        role: "toolResult", toolName: "subagent_wait", isError: false,
        details: { id: ID, status: "completed" }, content,
      },
    }]);
    assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
    assert.ok(existsSync(f.resultFile));
  });
}

test("persisted acknowledgement is authoritative even if delivered was not saved", (t) => {
  const f = fixture(t);
  f.save({ delivered: false, retentionEligibleAt: NOW - 60 * DAY });
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
});

for (const status of ["completed", "failed", "cancelled"]) {
  test(`successful saved subagent_wait acknowledges a ${status} Task`, (t) => {
    const f = fixture(t);
    f.save({ status, retentionEligibleAt: NOW - 60 * DAY });
    f.writeParent([f.owner, {
      type: "message", id: "wait", parentId: "owner",
      message: { role: "toolResult", toolName: "subagent_wait", isError: false, details: { id: ID, status }, content: [{ type: "text", text: "Done" }] },
    }]);
    assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  });
}

for (const [name, patch] of Object.entries({
  "failed tool call": { isError: true },
  "unknown success": { isError: undefined },
  "working result": { details: { id: ID, status: "working" } },
  "interrupted result": { details: { id: ID, status: "interrupted" } },
  "another Task": { details: { id: PARENT, status: "completed" } },
  "another tool": { toolName: "subagent_close" },
})) {
  test(`rejects acknowledgement from ${name}`, (t) => {
    const f = fixture(t);
    f.writeParent([f.owner, {
      type: "message", id: "wait", parentId: "owner",
      message: { role: "toolResult", toolName: "subagent_wait", isError: false, content: [{ type: "text", text: "Done" }], details: { id: ID, status: "completed" }, ...patch },
    }]);
    assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
    assert.equal(f.load().retentionEligibleAt, undefined);
  });
}

for (const patch of [
  { status: "working" }, { status: "waiting_for_human" }, { status: "interrupted" },
  { status: "completed", cleaned: false }, { status: "failed", cleaned: false },
  { status: "cancelled", cleaned: false },
]) {
  test(`protects ${patch.status} Tasks with cleaned=${patch.cleaned ?? true}`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY, ...patch });
    assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
    assert.ok(existsSync(f.resultFile));
    assert.ok(existsSync(f.childFile));
  });
}

test("a former child reused as another Task's parent keeps its conversation", (t) => {
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY });
  const otherId = "22222222-2222-4222-8222-222222222222";
  const otherDirectory = join(f.artifactRoot, otherId);
  mkdirSync(otherDirectory);
  writeFileSync(join(otherDirectory, "task.json"), JSON.stringify({
    schemaVersion: 1, id: otherId, agentSessionId: otherId, parentSessionId: ID,
    parentSessionFile: f.childFile, status: "working", cleaned: false,
  }));
  assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
  assert.ok(existsSync(f.childFile));
  assert.ok(existsSync(f.resultFile));
});

test("the acknowledgement must descend from the owning entry, not a sibling branch", (t) => {
  const f = fixture(t);
  f.writeParent([f.owner, { type: "message", id: "sibling", parentId: null }, { ...f.ack, parentId: "sibling" }]);
  assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
  f.writeParent([f.owner, { type: "message", id: "middle", parentId: "owner" }, { ...f.ack, parentId: "middle" }]);
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [], warnings: [] });
});

test("null ownership accepts a rooted acknowledgement", (t) => {
  const f = fixture(t);
  f.save({ parentEntryId: null });
  f.writeParent([{ ...f.ack, parentId: null }]);
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [], warnings: [] });
});

test("legacy receipts without a parent filename quietly await parent enrichment", (t) => {
  const f = fixture(t);
  f.save({ parentSessionFile: undefined });
  const before = readFileSync(f.manifestFile);
  assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
  assert.deepEqual(readFileSync(f.manifestFile), before);
});

test("dry run neither stamps newly eligible Tasks nor removes aged artifacts", (t) => {
  const f = fixture(t);
  const snapshot = () => [
    readFileSync(f.manifestFile, "utf8"), statSync(f.manifestFile).mtimeMs,
    readdirSync(f.directory), readdirSync(f.folder),
  ];
  let before = snapshot();
  assert.deepEqual(f.sweep({ dryRun: true }), { eligible: [ID], expired: [], warnings: [] });
  assert.deepEqual(snapshot(), before);
  f.save({ retentionEligibleAt: NOW - 30 * DAY });
  before = snapshot();
  assert.deepEqual(f.sweep({ dryRun: true }), { eligible: [ID], expired: [ID], warnings: [] });
  assert.deepEqual(snapshot(), before);
});

test("zero disables all store access, even for malformed paths and clocks", (t) => {
  const f = fixture(t);
  const before = readFileSync(f.manifestFile);
  assert.deepEqual(f.sweep({ retentionDays: 0, now: NaN, artifactRoot: null as any, sessionRoot: null as any }),
    { eligible: [], expired: [], warnings: [] });
  assert.deepEqual(readFileSync(f.manifestFile), before);
});

test("rejects invalid retention days and enabled clocks without touching the store", (t) => {
  const f = fixture(t);
  for (const retentionDays of [-1, 0.1, NaN, Infinity, -Infinity]) {
    assert.throws(() => f.sweep({ retentionDays }), /retentionDays/);
  }
  for (const now of [-1, NaN, Infinity]) assert.throws(() => f.sweep({ now }), /now/);
  assert.equal(f.load().retentionEligibleAt, undefined);
});

for (const target of ["resultFile", "childFile"] as const) {
  test(`recently modified ${target} postpones the whole Task until its 30-day boundary`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY });
    f.age(f[target], 30);
    assert.deepEqual(f.sweep({ now: NOW - 1 }), { eligible: [ID], expired: [], warnings: [] });
    assert.ok(existsSync(f.resultFile));
    assert.ok(existsSync(f.childFile));
    assert.equal(f.load().expiredAt, undefined);
    assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  });
}

test("discovers all exact child sessions at prune time without reading their full transcripts", (t) => {
  const f = fixture(t);
  f.sweep();
  const secondFolder = join(f.sessionRoot, "--other-project--");
  mkdirSync(secondFolder);
  const secondChild = join(secondFolder, `2026-02-01_${ID}.jsonl`);
  writeFileSync(secondChild, JSON.stringify({ type: "session", id: ID }) + "\n" + "not JSON".repeat(100_000));
  f.age(secondChild, 0);
  assert.deepEqual(f.sweep({ now: NOW + 30 * DAY }), { eligible: [ID], expired: [ID], warnings: [] });
  assert.ok(!existsSync(secondChild));
});

test("does not scan or delete legacy sessions without Task receipts", (t) => {
  const f = fixture(t);
  rmSync(f.manifestFile);
  writeFileSync(f.childFile, "malformed legacy data");
  assert.deepEqual(f.sweep(), { eligible: [], expired: [], warnings: [] });
  assert.equal(readFileSync(f.childFile, "utf8"), "malformed legacy data");
});

for (const [name, patch] of Object.entries({
  "wrong Task id": { id: PARENT },
  "wrong Agent id": { agentSessionId: PARENT },
  "wrong parent session": { parentSessionId: "another-parent" },
  "self-parenting": { parentSessionId: ID },
  "missing parent entry": { parentEntryId: undefined },
  "relative parent file": { parentSessionFile: "parent.jsonl" },
  "escaped Result directory": { resultDirectory: "/tmp" },
  "escaped Result file": { resultFile: "/tmp/result.json" },
  "escaped state file": { stateFile: "/tmp/state.json" },
  "invalid eligibility timestamp": { retentionEligibleAt: "old" },
  "negative eligibility timestamp": { retentionEligibleAt: -1 },
  "invalid expiry timestamp": { expiredAt: null },
  "expiry without eligibility": { expiredAt: NOW, retentionEligibleAt: undefined },
})) {
  test(`skips malformed ownership: ${name}`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY, ...patch });
    const outcome = f.sweep();
    assert.deepEqual(outcome.expired, []);
    assert.equal(outcome.warnings.length, 1);
    assert.ok(existsSync(f.resultFile));
    assert.ok(existsSync(f.childFile));
  });
}

for (const target of ["resultFile", "stateFile"] as const) {
  test(`never deletes the parent even when parentSessionFile names ${target}`, (t) => {
    const f = fixture(t);
    writeFileSync(f[target], readFileSync(f.parentFile));
    f.age(f[target]);
    f.save({ parentSessionFile: f[target], retentionEligibleAt: NOW - 60 * DAY });
    const outcome = f.sweep();
    assert.deepEqual(outcome.expired, []);
    assert.ok(existsSync(f[target]));
    assert.ok(existsSync(f.childFile));
  });
}

for (const kind of ["missing", "truncated", "duplicate entry", "broken link", "cycle", "wrong header"]) {
  test(`skips a ${kind} parent session`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY });
    if (kind === "missing") rmSync(f.parentFile);
    if (kind === "truncated") writeFileSync(f.parentFile, readFileSync(f.parentFile, "utf8") + '{"type":');
    if (kind === "duplicate entry") f.writeParent([f.owner, f.ack, f.ack]);
    if (kind === "broken link") f.writeParent([f.owner, { ...f.ack, parentId: "absent" }]);
    if (kind === "cycle") f.writeParent([f.owner, { ...f.ack, parentId: "ack" }]);
    if (kind === "wrong header") f.writeParent([f.owner, f.ack], { ...f.header, id: "other-parent" });
    const outcome = f.sweep();
    assert.deepEqual(outcome.eligible, []);
    assert.deepEqual(outcome.expired, []);
    assert.equal(outcome.warnings.length, 1);
    assert.ok(existsSync(f.resultFile));
    assert.ok(existsSync(f.childFile));
  });
}

for (const target of ["directory", "manifestFile", "resultFile", "stateFile", "parentFile", "childFile", "folder", "artifactRoot", "sessionRoot"] as const) {
  test(`refuses a symlink at ${target} without following or deleting it`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY });
    const source = f[target];
    const destination = join(f.root, "symlink-target");
    renameSync(source, destination);
    symlinkSync(destination, source);
    const outcome = f.sweep();
    assert.deepEqual(outcome.expired, []);
    assert.equal(outcome.warnings.length, 1);
    assert.ok(existsSync(f.resultFile));
    assert.ok(existsSync(f.childFile));
    assert.equal(f.load().expiredAt, undefined);
  });
}

for (const contents of [
  JSON.stringify({ type: "session", id: "another-child" }) + "\n",
  "not a header\n",
  " ".repeat(65536),
]) {
  test(`skips an uncertain child header of ${contents.length} bytes`, (t) => {
    const f = fixture(t);
    f.save({ retentionEligibleAt: NOW - 60 * DAY });
    writeFileSync(f.childFile, contents);
    f.age(f.childFile);
    const outcome = f.sweep();
    assert.deepEqual(outcome.expired, []);
    assert.equal(outcome.warnings.length, 1);
    assert.ok(existsSync(f.resultFile));
    assert.equal(readFileSync(f.childFile, "utf8"), contents);
  });
}

test("an expired receipt retries leftover files without changing its expiry timestamp", (t) => {
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY, expiredAt: NOW - DAY });
  rmSync(f.resultFile);
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  assert.equal(f.load().expiredAt, NOW - DAY);
  assert.ok(!existsSync(f.stateFile));
  assert.ok(!existsSync(f.childFile));
});

test("expiry retries still protect a recently modified child session", (t) => {
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY, expiredAt: NOW - DAY });
  rmSync(f.resultFile);
  f.age(f.childFile, 1);
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [], warnings: [] });
  assert.ok(existsSync(f.childFile));
  assert.ok(existsSync(f.stateFile));
});

test("records expiry before a partial deletion failure and retries remaining files", (t) => {
  if (process.getuid?.() === 0) return t.skip("root bypasses directory permissions");
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY });
  chmodSync(f.folder, 0o500);
  try {
    const outcome = f.sweep();
    assert.equal(outcome.warnings.length, 1);
    assert.equal(f.load().expiredAt, NOW);
    assert.deepEqual(outcome.expired, [ID], "reports partial pruning alongside its warning");
    assert.ok(!existsSync(f.resultFile));
    assert.ok(!existsSync(f.stateFile));
    assert.ok(existsSync(f.childFile));
  } finally { chmodSync(f.folder, 0o700); }
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  assert.ok(!existsSync(f.childFile));
  assert.equal(f.load().expiredAt, NOW);
});

test("discovery ignores direct-root, nested, and inexact filenames even with matching headers", (t) => {
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY });
  const nested = join(f.folder, "nested");
  mkdirSync(nested);
  const excluded = [
    join(f.sessionRoot, `2025-01-01_${ID}.jsonl`),
    join(nested, `2025-01-01_${ID}.jsonl`),
    join(f.folder, `2025-01-01_prefix${ID}.jsonl`),
    join(f.folder, `2025-01-01_${ID}.jsonl.bak`),
    join(f.folder, `${ID}.jsonl`),
  ];
  for (const file of excluded) {
    writeFileSync(file, JSON.stringify({ type: "session", id: ID }) + "\n");
    f.age(file);
  }
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  for (const file of excluded) assert.ok(existsSync(file), file);
});

test("missing optional artifacts do not prevent expiry of a cancelled Task", (t) => {
  const f = fixture(t);
  f.save({ status: "cancelled", retentionEligibleAt: NOW - 60 * DAY });
  rmSync(f.resultFile);
  rmSync(f.stateFile);
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
  assert.equal(f.load().expiredAt, NOW);
  assert.ok(!existsSync(f.childFile));
});

test("empty stores do not get created by either preview or apply", (t) => {
  const f = fixture(t);
  const absent = join(f.root, "absent");
  for (const dryRun of [true, false]) {
    assert.deepEqual(f.sweep({ artifactRoot: absent, dryRun }), { eligible: [], expired: [], warnings: [] });
    assert.ok(!existsSync(absent));
  }
});

test("a failed durable receipt update deletes nothing", (t) => {
  if (process.getuid?.() === 0) return t.skip("root bypasses directory permissions");
  const f = fixture(t);
  f.save({ retentionEligibleAt: NOW - 60 * DAY });
  chmodSync(f.directory, 0o500);
  try {
    const outcome = f.sweep();
    assert.deepEqual(outcome.expired, []);
    assert.equal(outcome.warnings.length, 1);
    assert.equal(f.load().expiredAt, undefined);
    assert.ok(existsSync(f.resultFile));
    assert.ok(existsSync(f.childFile));
  } finally { chmodSync(f.directory, 0o700); }
  assert.deepEqual(f.sweep(), { eligible: [ID], expired: [ID], warnings: [] });
});
