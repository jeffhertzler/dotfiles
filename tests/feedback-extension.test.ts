import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { collectAssistantCaptures, installFeedbackExtension, createHerdrFeedbackReader, type FeedbackReader } from "../dot_pi/agent/extensions/feedback.ts";

function assistant(id: string, parentId: string | null, text: string, stopReason = "stop"): any {
  return { type: "message", id, parentId, timestamp: "2026-09-22T12:00:00.000Z", message: {
    role: "assistant", content: [{ type: "text", text }], stopReason,
  } };
}
function user(id: string, parentId: string | null, text: string): any {
  return { type: "message", id, parentId, timestamp: "2026-09-22T11:59:00.000Z", message: { role: "user", content: text } };
}

function harness(t: test.TestContext) {
  const root = mkdtempSync(join(tmpdir(), "pi-feedback-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const entries = [user("u1", null, "Explain the migration"), assistant("a1", "u1", "# First reply\n\nDetails."),
    user("u2", "a1", "What changed?"), assistant("a2", "u2", "# Latest reply\n\nEverything tested."),
    assistant("progress", "a2", "Checking files...", "toolUse"),
    user("other-user", "a1", "An alternative question"), assistant("alternate", "other-user", "# Alternative answer")];
  let branch = entries.slice(0, 5);
  let editor = "";
  let sessionId = "session-1";
  let open = false;
  const requests: any[] = [];
  const notices: Array<{ message: string; level: string }> = [];
  const events: any[] = [];
  const commands = new Map<string, any>();
  const handlers = new Map<string, any>();
  const reader: FeedbackReader = {
    async isOpen() { return open; },
    async focus(handle) { requests.push({ focus: handle }); },
    async open(request) {
      requests.push(request); open = true;
      return { paneId: "w1:p2", terminalId: "term_reader", socketPath: "/socket" };
    },
  };
  const pi: any = {
    registerCommand(name: string, options: any) { commands.set(name, options); },
    on(event: string, handler: any) { handlers.set(event, handler); },
    events: { emit: (...args: any[]) => events.push(args) },
    sendMessage() { assert.fail("reading never injects a message"); },
    sendUserMessage() { assert.fail("feedback is never automatically sent"); },
  };
  const ctx: any = {
    mode: "tui", cwd: "/repo", isIdle: () => false,
    waitForIdle() { assert.fail("reading must work while the model is busy"); },
    sessionManager: {
      getSessionId: () => sessionId, getSessionDir: () => root, getSessionFile: () => join(root, `${sessionId}.jsonl`),
      getEntries: () => entries, getBranch: () => branch,
    },
    ui: {
      notify(message: string, level: string) { notices.push({ message, level }); },
      getEditorText: () => editor, setEditorText: (text: string) => { editor = text; },
      select() { assert.fail("opening latest must not show a Pi picker"); },
      custom() { assert.fail("reader must not take over or stop the Pi TUI"); },
    },
  };
  installFeedbackExtension(pi, { reader });
  const run = (args = "") => commands.get("feedback").handler(args, ctx);
  const directory = join(root, "feedback", "session-1");
  const catalogue = () => JSON.parse(readFileSync(join(directory, "catalogue.json"), "utf8"));
  const submit = (id = "a2", patch: any = {}) => {
    const path = join(directory, id, "feedback.json");
    writeFileSync(path, JSON.stringify({ schemaVersion: 1, piSessionId: "session-1", assistantMessageId: id,
      sourcePath: join(directory, id, "source.md"), submittedAt: "now",
      comments: [{ id: "feedback-1", body: "Explain this", startLine: 1, endLine: 1, quotedText: ["# Latest reply"] }], ...patch }));
    return path;
  };
  return { root, pi, entries, notices, events, requests, commands, handlers, reader, ctx, run, directory, catalogue, submit,
    setBranch: (value: any[]) => { branch = value; }, setSession: (value: string) => { sessionId = value; },
    setEditor: (value: string) => { editor = value; }, editor: () => editor, close: () => { open = false; } };
}

test("assistant captures include full tree text but exclude streaming/deferred responses", () => {
  assert.deepEqual(collectAssistantCaptures([
    user("u1", null, "Prompt"), assistant("a1", "u1", "Reply"), assistant("a2", "u1", "Other reply"),
    assistant("partial", "a2", "Streaming...", "pending"), assistant("deferred", "a2", "Pending result", "deferred"),
  ]), [{ entryId: "a1", markdown: "Reply" }, { entryId: "a2", markdown: "Other reply" }]);
});

test("busy Pi opens latest finished current-branch reply without picker, idle wait, attention suppression, or editor takeover", async (t) => {
  const h = harness(t);
  await h.run();
  assert.equal(h.requests.length, 1);
  assert.equal(h.catalogue().latestEntryId, "a2");
  assert.equal(h.catalogue().messages.find((m: any) => m.entryId === "progress").finished, false);
  assert.equal(h.catalogue().messages.find((m: any) => m.entryId === "alternate").onBranch, false);
  assert.equal(h.catalogue().messages.find((m: any) => m.entryId === "a2").prompt, "What changed?");
  assert.equal(h.catalogue().messages.find((m: any) => m.entryId === "alternate").prompt, "An alternative question");
  assert.equal(h.catalogue().messages.find((m: any) => m.entryId === "a2").title, "Latest reply");
  assert.equal(h.requests[0].feedbackStatePath, join(h.directory, "a2", "annotations.json"));
  assert.deepEqual(h.events, [], "no long-lived suppression can hide a genuine question from the working agent");
  assert.equal(h.editor(), "");
  assert.equal(statSync(join(h.directory, "a2", "source.md")).mode & 0o777, 0o600);
});

for (const scenario of ["empty", "progress-only", "other-branch-only"]) {
  test(`no completed current-branch reply does not silently substitute another message: ${scenario}`, async (t) => {
    const h = harness(t);
    if (scenario === "empty") h.entries.splice(0);
    h.setBranch(scenario === "progress-only" ? [h.entries[4]] : []);
    await h.run();
    assert.equal(h.requests.length, 0);
    assert.equal(h.catalogue().latestEntryId, "");
    assert.match(h.notices.at(-1)!.message, /No completed reply yet/);
  });
}

test("an existing reader stays available to browse after switching to a branch without a completed reply", async (t) => {
  const h = harness(t);
  await h.run();
  h.setBranch([]);
  h.handlers.get("session_tree")({}, h.ctx);
  await h.run();
  assert.equal(h.catalogue().latestEntryId, "");
  assert.ok(h.requests[1].focus);
});

test("new completed replies refresh catalogue without overwriting old text, drafts, or staged input", async (t) => {
  const h = harness(t);
  await h.run();
  const old = readFileSync(join(h.directory, "a2", "source.md"), "utf8");
  const draftPath = join(h.directory, "a2", "annotations.json");
  writeFileSync(draftPath, "draft annotations");
  h.setEditor("A question I am typing");
  h.entries[3].message.content[0].text = "Changed upstream history";
  const next = assistant("a3", "progress", "# New reply\n\nReady.");
  h.entries.push(next);
  h.setBranch([...h.ctx.sessionManager.getBranch(), next]);
  h.handlers.get("turn_end")({}, h.ctx);
  assert.equal(h.catalogue().latestEntryId, "a3");
  assert.equal(readFileSync(join(h.directory, "a2", "source.md"), "utf8"), old);
  assert.equal(readFileSync(draftPath, "utf8"), "draft annotations");
  assert.equal(h.catalogue().messages.find((m: any) => m.entryId === "a2").title, "Latest reply");
  assert.equal(h.requests.length, 1);
  assert.equal(h.editor(), "A question I am typing");
});

test("opening twice and reloading reuse the owned reader without wiping submissions", async (t) => {
  const h = harness(t);
  await h.run();
  const submitted = h.submit();
  const before = readFileSync(submitted);
  installFeedbackExtension(h.pi, { reader: h.reader });
  h.handlers.get("session_start")({}, h.ctx);
  await h.run();
  assert.ok(h.requests[1].focus);
  assert.deepEqual(readFileSync(submitted), before);
  h.close();
  await h.run();
  assert.equal(h.requests.length, 3);
  assert.ok(h.requests[2].cataloguePath);
});

test("remote reader handles survive reload and protect drafts until that reader closes", async (t) => {
  const h = harness(t);
  const open = h.reader.open;
  h.reader.open = async (request) => {
    await open(request);
    return { kind: "nvim", server: "/nvim.sock", cataloguePath: request.cataloguePath };
  };
  await h.run(); h.submit();
  installFeedbackExtension(h.pi, { reader: h.reader });
  await h.run();
  assert.equal(h.requests[1].focus.kind, "nvim");
  await h.run("clear");
  assert.ok(existsSync(h.directory));
  h.close(); await h.run("clear");
  assert.equal(existsSync(h.directory), false);
});

test("a malformed or cross-conversation remote handle cannot authorize clearing drafts", async (t) => {
  const h = harness(t);
  await h.run(); h.submit(); h.close();
  for (const handle of [null, {kind:"nvim",server:"/nvim.sock",cataloguePath:"/another/catalogue.json"}, {kind:"unexpected",paneId:"x",terminalId:"x",socketPath:""}]) {
    writeFileSync(join(h.directory, "reader.json"), JSON.stringify(handle));
    await h.run("clear");
    assert.ok(existsSync(join(h.directory, "a2", "feedback.json")));
    assert.match(h.notices.at(-1)!.message, /Invalid feedback reader identity/);
  }
});

test("there is no collection command or Pi-side input replacement", async (t) => {
  const h = harness(t);
  await h.run(); h.submit(); h.setEditor("My pending input");
  h.ctx.ui.setEditorText = () => assert.fail("Agent Bridge owns staging, not the feedback extension");
  await h.run("collect");
  assert.equal(h.editor(), "My pending input");
  assert.match(h.notices.at(-1)!.message, /^Usage: \/feedback \[clear\]$/);
  assert.equal(existsSync(join(h.directory, "a2", "collected.json")), false);
});

test("clear refuses a live reader but removes saved drafts once it closes; passive events do not recreate them", async (t) => {
  const h = harness(t);
  await h.run(); h.submit();
  await h.run("clear");
  assert.ok(existsSync(h.directory));
  assert.match(h.notices.at(-1)!.message, /Close the feedback reader/);
  h.close(); await h.run("clear");
  assert.equal(existsSync(h.directory), false);
  h.handlers.get("turn_end")({}, h.ctx);
  assert.equal(existsSync(h.directory), false);
});

test("session switches cannot refresh another conversation's drafts", async (t) => {
  const h = harness(t);
  await h.run(); h.submit();
  const before = readFileSync(join(h.directory, "catalogue.json"));
  h.setSession("session-2");
  h.handlers.get("session_start")({}, h.ctx);
  assert.equal(h.editor(), "");
  assert.deepEqual(readFileSync(join(h.directory, "catalogue.json")), before);
});

test("an in-flight reopen stays bound to its original session across a session switch", async (t) => {
  const h = harness(t);
  await h.run();
  let release!: () => void;
  h.reader.isOpen = async () => { await new Promise<void>((r) => { release = r; }); return false; };
  const opening = h.run();
  h.setSession("session-2");
  release(); await opening;
  assert.equal(existsSync(join(h.root, "feedback", "session-2")), false);
  assert.equal(h.requests[1].cataloguePath, join(h.directory, "catalogue.json"));
});

test("concurrent open requests launch one reader", async (t) => {
  const h = harness(t);
  const original = h.reader.open;
  let release!: () => void;
  h.reader.open = async (request) => { await new Promise<void>((r) => { release = r; }); return original(request); };
  const first = h.run();
  await Promise.resolve();
  await h.run();
  release(); await first;
  assert.equal(h.requests.length, 1);
  assert.match(h.notices[0].message, /already opening/);
});

test("uncertain launch retains reader identity so retries cannot open duplicate editors", async (t) => {
  const h = harness(t);
  const original = h.reader.open;
  h.reader.open = async (request) => {
    const handle = await original(request);
    throw Object.assign(new Error("Response lost"), { readerHandle: handle });
  };
  await h.run();
  await h.run();
  assert.equal(h.requests.length, 2);
  assert.ok(h.requests[1].focus);
});

test("Herdr launcher splits the calling pane and uses safely quoted asynchronous pane commands", async () => {
  const calls: string[][] = [];
  const pi: any = { async exec(_command: string, args: string[]) {
    calls.push(args);
    const result = args[1] === "layout" ? { layout: { panes: [{ pane_id: "w1:p1", rect: { width: 160 } }] } }
      : args[1] === "split" ? { pane: { pane_id: "w1:p2", terminal_id: "term_reader" } } : {};
    return { code: 0, stderr: "", stdout: args[1] === "run" ? "" : JSON.stringify({ result }) };
  } };
  const reader = createHerdrFeedbackReader(pi, { HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", PI_FEEDBACK_NVIM: "/bin/editor's nvim" });
  await reader.open({ cataloguePath: "/tmp/snapshot ' quote/catalogue.json", feedbackStatePath: "/tmp/state.json", cwd: "/repo" });
  assert.deepEqual(calls[1], ["pane", "split", "--current", "--direction", "right", "--cwd", "/repo", "--focus"]);
  assert.equal(calls[2][2], "w1:p2");
  assert.ok(calls[2][3].includes("'\\''"), "single quotes cannot escape shell arguments");
  assert.match(calls[2][3], /feedback_reader/);
  assert.match(calls[2][3], /herdr pane close 'w1:p2'/);
});

test("Herdr launcher distinguishes missing panes from connectivity errors and foreign sessions", async () => {
  let code = "pane_not_found";
  const reader = createHerdrFeedbackReader({ exec: async () => ({ code: 1, stdout: "", stderr: JSON.stringify({ error: { code } }) }) } as any, {});
  const handle = { paneId: "w1:p2", terminalId: "term", socketPath: "" };
  assert.equal(await reader.isOpen(handle), false);
  code = "connection_failed";
  await assert.rejects(reader.isOpen(handle), /herdr/);
  await assert.rejects(reader.isOpen({ ...handle, socketPath: "/another" }), /another Herdr session/);
  await assert.rejects(reader.open({ cataloguePath: "/tmp/catalogue.json", feedbackStatePath: "/tmp/state.json", cwd: "/repo" }), /requires Herdr/);
});
