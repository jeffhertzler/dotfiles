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

test("standalone readers use the same exact-pane focus even outside the calling tab", async (t) => {
  const h = await harness(t);
  const standalone = createHerdrFeedbackReader(h.pi, h.env);
  await standalone.focus(h.paneHandle);
  assert.equal(h.focusRequests[0].method, "pane.focus");
  assert.deepEqual(h.focusRequests[0].params, { pane_id: h.paneHandle.paneId });
  assert.equal(h.calls.length, 0, "no directional neighbour search");
  h.failFocus();
  await assert.rejects(standalone.focus(h.paneHandle), /Focus failed/);
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
