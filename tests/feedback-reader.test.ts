import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createFeedbackReader, createHerdrFeedbackReader, type PaneReaderHandle, type ReaderHandle } from "../dot_pi/agent/extensions/feedback/reader.ts";

async function harness(t: test.TestContext) {
  const root = mkdtempSync(join(tmpdir(), "feedback-reuse-"));
  const socketPath = join(root, "herdr.sock");
  const focusRequests: any[] = [];
  let focusError = false;
  const socket = createServer((client) => client.on("data", (data) => {
    const request = JSON.parse(data.toString()); focusRequests.push(request);
    client.end(JSON.stringify({ id: request.id, ...(focusError ? { error: { message: "Focus failed" } } : { result: {} }) }) + "\n");
  }));
  await new Promise<void>((resolve) => socket.listen(socketPath, resolve));
  t.after(async () => { await new Promise<void>((resolve) => socket.close(() => resolve())); rmSync(root, { recursive: true, force: true }); });
  mkdirSync(join(root, "herdr-nvim"));
  const env: Record<string, string> = { HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", HERDR_TAB_ID: "w1:t1", HERDR_WORKSPACE_ID: "w1", HERDR_SOCKET_PATH: socketPath, XDG_RUNTIME_DIR: root };
  const panes: any[] = [];
  const editors = new Map<string, any>();
  const calls: Array<{ command: string; args: string[]; request?: any }> = [];
  const openReaders = new Set<string>();
  let fallbackOpens = 0, failAction = "", invalidAction = "", timeout = false, listError = false;
  const paneHandle = { paneId: "w1:new", terminalId: "terminal-fallback", socketPath };
  const fallbackCalls: any[] = [];
  const fallback = {
    async open() { fallbackOpens++; return paneHandle; },
    async focus(handle: PaneReaderHandle) { fallbackCalls.push(["focus", handle]); },
    async isOpen(handle: PaneReaderHandle) { fallbackCalls.push(["isOpen", handle]); return true; },
  };
  const pi: any = { async exec(command: string, args: string[]) {
    const call: any = { command, args }; calls.push(call);
    if (command === "herdr") {
      if (listError) return { code: 1, stdout: "", stderr: "Server unavailable" };
      return { code: 0, stderr: "", stdout: JSON.stringify({ result: args[1] === "list" ? { panes } : { pane: panes.find(p => p.pane_id === args[2]) } }) };
    }
    assert.equal(command, "nvim");
    const server = args[args.indexOf("--server") + 1];
    const editor = editors.get(server);
    if (!editor) return { code: 2, stdout: "", stderr: `E247: Failed to connect to '${server}': connection refused. Send expression failed.` };
    if (timeout) return { code: 0, killed: true, stdout: "", stderr: "" };
    const outer = args.at(-1)!.match(/decode\(\[\[(.*?)\]\]\)/)![1];
    const lua = Buffer.from(outer, "base64").toString();
    const payload = lua.match(/decode\(\[\[(.*?)\]\]\)/);
    if (!payload) return { code: 0, stdout: JSON.stringify(editor), stderr: "" };
    const request = JSON.parse(Buffer.from(payload[1], "base64").toString()); call.request = request;
    if (request.action === failAction) return { code: 1, stderr: "RPC response lost", stdout: "" };
    if (request.action === invalidAction) return { code: 0, stderr: "", stdout: JSON.stringify({ ok: false, error: "Invalid catalogue" }) };
    const key = `${server}:${request.cataloguePath}`;
    if (request.action === "open") openReaders.add(key);
    return { code: 0, stderr: "", stdout: JSON.stringify({ ok: true, open: openReaders.has(key) }) };
  } };
  function editor(id: string, tab = "w1:t1", patch: any = {}) {
    const pane = { pane_id: `w1:${id}`, terminal_id: `term-${id}`, workspace_id: "w1", tab_id: tab };
    panes.push(pane);
    const server = join(root, `${id}.sock`);
    editors.set(server, { version: 1, paneId: pane.pane_id, socketPath, dedicated: false, ...patch });
    writeFileSync(join(root, "herdr-nvim", `${pane.pane_id.replace(/:/g, "_")}.server`), `${server}\n`);
    return server;
  }
  const reader = () => createFeedbackReader(pi, env, { fallback });
  const request = { cataloguePath: join(root, "Pi's catalogue.json"), feedbackStatePath: join(root, "annotations.json"), cwd: "/repo" };
  return { pi, env, reader, request, editor, panes, editors, calls, focusRequests, openReaders, fallbackCalls, paneHandle,
    fallbackOpens: () => fallbackOpens, fail: (action: string) => { failAction = action; }, invalid: (action: string) => { invalidAction = action; },
    setTimeout: () => { timeout = true; }, failFocus: () => { focusError = true; }, failList: () => { listError = true; } };
}

for (const legacy of [true, false]) {
  test(`dedicated pane focus restores its response through RPC after switching to code (${legacy ? "legacy" : "catalogue-bound"} handle)`, async (t) => {
    const h = await harness(t);
    const server = h.editor("dedicated", "w1:t2", { dedicated: true, cataloguePath: h.request.cataloguePath });
    const pane = h.panes[0];
    const handle: PaneReaderHandle = JSON.parse(JSON.stringify({ paneId: pane.pane_id, terminalId: pane.terminal_id,
      socketPath: h.env.HERDR_SOCKET_PATH, ...(!legacy ? { cataloguePath: h.request.cataloguePath } : {}) }));
    h.openReaders.add(`${server}:${h.request.cataloguePath}`);
    const reader = createFeedbackReader(h.pi, h.env);
    assert.equal(await reader.isOpen(handle), true, "a code buffer does not close the owned reader pane");
    await reader.focus(handle);
    assert.deepEqual(h.calls.filter(call => call.request).map(call => call.request), [
      { action: "focus", cataloguePath: h.request.cataloguePath },
    ], "pane focus alone cannot restore the response buffer; focus the existing reader, never reopen/reset it");
    assert.deepEqual(h.focusRequests.map(request => [request.method, request.params]), [
      ["pane.focus", { pane_id: pane.pane_id }],
    ]);
    assert.ok(h.calls.filter(call => call.command === "nvim").every(call => call.args.includes(server)), "only the exact pane's registered server is contacted");
    assert.ok(h.calls.filter(call => call.command === "herdr").every(call => call.args[1] === "get"), "no neighbour search or launch");
    h.failFocus();
    await assert.rejects(reader.focus(handle), /Focus failed/);
  });
}

for (const failure of ["terminal", "pane", "session", "missing-registry", "empty-registry", "dead-server", "foreign-editor", "foreign-socket",
  "shared-editor", "missing-catalogue", "relative-catalogue", "unnormalized-catalogue", "different-catalogue", "old-plugin", "timeout",
  "rpc-error", "rpc-rejected", "closed-reader"]) {
  test(`dedicated focus fails closed without editor takeover or plain pane focus: ${failure}`, async (t) => {
    const h = await harness(t);
    const patch = failure === "foreign-editor" ? { paneId: "w1:other" }
      : failure === "foreign-socket" ? { socketPath: "/foreign.sock" }
      : failure === "shared-editor" ? { dedicated: false }
      : failure === "missing-catalogue" ? { cataloguePath: undefined }
      : failure === "relative-catalogue" ? { cataloguePath: "relative.json" }
      : failure === "unnormalized-catalogue" ? { cataloguePath: "/tmp/../catalogue.json" }
      : failure === "different-catalogue" ? { cataloguePath: "/another/catalogue.json" }
      : failure === "old-plugin" ? { version: 0 } : {};
    const server = h.editor("dedicated", "w1:t2", { dedicated: true, cataloguePath: h.request.cataloguePath, ...patch });
    const pane = h.panes[0];
    const handle: PaneReaderHandle = { kind: "pane", paneId: pane.pane_id, terminalId: pane.terminal_id,
      socketPath: h.env.HERDR_SOCKET_PATH, cataloguePath: h.request.cataloguePath };
    h.openReaders.add(`${server}:${h.request.cataloguePath}`);
    // Even explicit/shared editor hints must not redirect an owned reader.
    h.env.NVIM_SERVER = h.editor("other");
    const registryFile = join(h.env.XDG_RUNTIME_DIR, "herdr-nvim", "w1_dedicated.server");
    if (failure === "terminal") pane.terminal_id = "replacement-terminal";
    if (failure === "pane") pane.pane_id = "w1:replaced";
    if (failure === "session") h.env.HERDR_SOCKET_PATH = "/another-session.sock";
    if (failure === "missing-registry") rmSync(registryFile);
    if (failure === "empty-registry") writeFileSync(registryFile, "\n");
    if (failure === "dead-server") h.editors.delete(server);
    if (failure === "timeout") h.setTimeout();
    if (failure === "rpc-error") h.fail("focus");
    if (failure === "rpc-rejected") h.invalid("focus");
    if (failure === "closed-reader") h.openReaders.clear();
    const reader = createHerdrFeedbackReader(h.pi, h.env);
    await assert.rejects(reader.focus(handle));
    assert.equal(h.focusRequests.length, 0, "never report success by merely focusing a pane");
    assert.ok(h.calls.filter(call => call.command === "nvim").every(call => call.args.includes(server)));
    assert.ok(h.calls.filter(call => call.command === "herdr").every(call => call.args[1] === "get"), "no competing editor/pane launch");
    assert.ok(h.calls.filter(call => call.request).every(call => call.request.action === "focus"));
    if (!["rpc-error", "rpc-rejected", "closed-reader"].includes(failure)) {
      assert.equal(h.calls.filter(call => call.request).length, 0, "identity must be verified before mutating the reader");
    }
  });
}

test("legacy dedicated ownership remains conservative for clear, even when RPC discovery is unavailable", async (t) => {
  const h = await harness(t);
  h.panes.push({ pane_id: h.paneHandle.paneId, terminal_id: h.paneHandle.terminalId });
  const reader = createHerdrFeedbackReader(h.pi, h.env);
  assert.equal(await reader.isOpen(h.paneHandle), true, "missing registry cannot authorize deleting drafts");
  await assert.rejects(reader.focus(h.paneHandle), /not registered/);
  assert.equal(await reader.isOpen(h.paneHandle), true);
  h.panes[0].terminal_id = "replacement";
  assert.equal(await reader.isOpen(h.paneHandle), false);
});

test("new dedicated launches persist catalogue identity, including uncertain launch failures", async () => {
  let failed = false;
  const pi: any = { async exec(_command: string, args: string[]) {
    if (args[1] === "run" && failed) return { code: 1, stderr: "Response lost", stdout: "" };
    return { code: 0, stderr: "", stdout: JSON.stringify({ result: args[1] === "split"
      ? { pane: { pane_id: "w1:reader", terminal_id: "term-reader" } } : {} }) };
  } };
  const reader = createHerdrFeedbackReader(pi, { HERDR_ENV: "1", HERDR_PANE_ID: "w1:caller", HERDR_SOCKET_PATH: "/herdr.sock" });
  const request = { cataloguePath: "/feedback/catalogue.json", feedbackStatePath: "/feedback/state.json", cwd: "/repo" };
  const handle = await reader.open(request);
  assert.deepEqual(handle, { paneId: "w1:reader", terminalId: "term-reader", socketPath: "/herdr.sock", cataloguePath: request.cataloguePath });
  failed = true;
  await assert.rejects(reader.open(request), (error: any) => {
    assert.deepEqual(error.readerHandle, handle);
    return /Response lost/.test(error.message);
  });
});

test("reuses same-tab Neovim, passes paths as data, and focuses exact pane without a process/pane launch", async (t) => {
  const h = await harness(t);
  const server = h.editor("editor"); h.editor("elsewhere", "w1:t2");
  const handle = await h.reader().open(h.request);
  assert.equal(handle.kind, "nvim");
  assert.equal((handle as any).server, server);
  assert.equal(h.fallbackOpens(), 0);
  assert.deepEqual(h.calls.find(call => call.request?.action === "open")!.request, { action: "open", cataloguePath: h.request.cataloguePath, feedbackStatePath: h.request.feedbackStatePath });
  assert.equal(h.focusRequests[0].method, "pane.focus");
  assert.deepEqual(h.focusRequests[0].params, { pane_id: "w1:editor" });
  assert.ok(h.calls.every(call => !call.args.includes("split") && !call.args.includes("run") && !call.args.includes("close")));
});

test("reuses a unique editor elsewhere in the same workspace", async (t) => {
  const h = await harness(t); const server = h.editor("editor", "w1:t2");
  assert.equal((await h.reader().open(h.request) as any).server, server);
});

test("falls back only when no suitable live editor exists, including stale registry and dedicated readers", async (t) => {
  const h = await harness(t);
  const dead = h.editor("dead"); h.editors.delete(dead);
  h.editor("dedicated", "w1:t1", { dedicated: true });
  h.editor("foreign", "w1:t1", { socketPath: "/different-herdr.sock" });
  h.editor("reassigned", "w1:t1", { paneId: "w1:another" });
  const handle = await h.reader().open(h.request);
  assert.deepEqual(handle, h.paneHandle);
  assert.equal(h.fallbackOpens(), 1);
  assert.equal(h.focusRequests.length, 0);
});

test("ambiguous editors never cause an arbitrary choice or an extra process", async (t) => {
  const h = await harness(t); h.editor("one"); h.editor("two");
  await assert.rejects(h.reader().open(h.request), /Multiple Neovim/);
  assert.equal(h.fallbackOpens(), 0);
  assert.equal(h.calls.filter(call => call.request).length, 0);
});

test("an explicit Neovim server resolves ambiguity without touching another editor", async (t) => {
  const h = await harness(t); h.editor("one"); h.env.NVIM_SERVER = h.editor("two");
  assert.equal((await h.reader().open(h.request) as any).server, h.env.NVIM_SERVER);
  assert.equal(h.calls.filter(call => call.command === "nvim" && call.args.includes(h.env.NVIM_SERVER)).length, 3);
});

for (const failure of ["old-plugin", "timeout", "herdr-error", "invalid-catalogue", "lost-response", "focus-error"]) {
  test(`uncertain/unsafe reuse never launches a competing fallback: ${failure}`, async (t) => {
    const h = await harness(t); h.editor("editor", "w1:t1", failure === "old-plugin" ? { version: 0 } : {});
    if (failure === "timeout") h.setTimeout();
    if (failure === "herdr-error") h.failList();
    if (failure === "invalid-catalogue") h.invalid("open");
    if (failure === "lost-response") h.fail("open");
    if (failure === "focus-error") h.failFocus();
    let error: any;
    await assert.rejects(h.reader().open(h.request), (caught) => { error = caught; return true; });
    assert.equal(h.fallbackOpens(), 0);
    if (["invalid-catalogue", "lost-response", "focus-error"].includes(failure)) {
      assert.equal(error.readerHandle.kind, "nvim");
      assert.equal(error.readerHandle.cataloguePath, h.request.cataloguePath);
    }
    if (failure === "old-plugin") assert.match(error.message, /Restart Neovim/);
  });
}

test("restored remote handles check and focus their own catalogue; a closed tab is not a live reader", async (t) => {
  const h = await harness(t); const server = h.editor("editor");
  const handle = JSON.parse(JSON.stringify(await h.reader().open(h.request))) as ReaderHandle;
  const reloaded = h.reader();
  assert.equal(await reloaded.isOpen(handle), true);
  await reloaded.focus(handle);
  assert.equal(h.calls.filter(call => call.request?.action === "open").length, 1);
  h.openReaders.delete(`${server}:${h.request.cataloguePath}`);
  assert.equal(await reloaded.isOpen(handle), false);
  await reloaded.open(h.request);
  assert.equal(h.fallbackOpens(), 0);
});

test("server death and probe errors are distinguished for safe clear/reopen", async (t) => {
  const h = await harness(t); const server = h.editor("editor");
  const handle = await h.reader().open(h.request);
  h.fail("status");
  await assert.rejects(h.reader().isOpen(handle), /RPC/);
  h.editors.delete(server);
  assert.equal(await h.reader().isOpen(handle), false);
  assert.equal(h.fallbackOpens(), 0);
});

test("remote handles cannot be operated from another Herdr session", async (t) => {
  const h = await harness(t); h.editor("editor");
  const handle = await h.reader().open(h.request);
  h.env.HERDR_SOCKET_PATH = "/different-session";
  await assert.rejects(h.reader().isOpen(handle), /another Herdr session/);
  await assert.rejects(h.reader().focus(handle), /another Herdr session/);
});

test("legacy pane handles keep the existing ownership and focus behavior", async (t) => {
  const h = await harness(t);
  assert.equal(await h.reader().isOpen(h.paneHandle), true);
  await h.reader().focus(h.paneHandle);
  assert.deepEqual(h.fallbackCalls, [["isOpen", h.paneHandle], ["focus", h.paneHandle]]);
});
