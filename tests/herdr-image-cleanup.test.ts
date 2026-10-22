import assert from "node:assert/strict";
import test from "node:test";
import herdrImageCleanup from "../dot_pi/agent/extensions/herdr-image-cleanup.ts";

const deleteVisibleImages = "\x1b_Ga=d,d=A,q=2;\x1b\\";

function harness(overrides: Record<string, unknown> = {}) {
  const writes: string[] = [];
  const exits: (() => void)[] = [];
  let shutdown: (event: any, ctx: any) => void;
  herdrImageCleanup({
    on(event: string, handler: typeof shutdown) {
      assert.equal(event, "session_shutdown");
      shutdown = handler;
    },
  } as any, {
    termProgram: "herdr",
    isTTY: true,
    onExit: (callback: () => void) => exits.push(callback),
    write: (sequence: string) => { writes.push(sequence); },
    ...overrides,
  });
  return { writes, exits, shutdown: (reason: string, mode = "tui") => shutdown({ reason }, { mode }) };
}

test("cleans visible Herdr images only at process exit, after terminal shutdown", () => {
  const h = harness();
  h.shutdown("quit");
  assert.deepEqual(h.writes, [], "shutdown can run before the terminal is restored on signal exits");
  assert.equal(h.exits.length, 1);
  h.writes.push("terminal restored");
  h.exits[0]();
  assert.deepEqual(h.writes, ["terminal restored", deleteVisibleImages]);
});

test("reloads and session changes neither clear images nor leave exit handlers", () => {
  const h = harness();
  for (const reason of ["reload", "new", "resume", "fork"]) h.shutdown(reason);
  assert.deepEqual(h.writes, []);
  assert.deepEqual(h.exits, []);
  h.shutdown("quit");
  assert.equal(h.exits.length, 1);
});

test("does not write graphics into RPC, JSON, print, redirected output, or other terminals", () => {
  for (const mode of ["rpc", "json", "print"]) {
    const h = harness();
    h.shutdown("quit", mode);
    assert.deepEqual(h.exits, []);
  }
  for (const overrides of [{ isTTY: false }, { termProgram: "ghostty" }, { termProgram: undefined }]) {
    const h = harness(overrides);
    h.shutdown("quit");
    assert.deepEqual(h.exits, []);
  }
});

test("repeated shutdown notifications schedule one cleanup", () => {
  const h = harness();
  h.shutdown("quit");
  h.shutdown("quit");
  assert.equal(h.exits.length, 1);
});

test("a disconnected terminal cannot turn cleanup into an exit failure", () => {
  const h = harness({ write: () => { throw new Error("EIO"); } });
  h.shutdown("quit");
  assert.doesNotThrow(() => h.exits[0]());
});
