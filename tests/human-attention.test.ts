import assert from "node:assert/strict";
import test from "node:test";

import {
  HUMAN_ATTENTION_NOTIFICATIONS_SUPPRESSED,
  HUMAN_ATTENTION_REQUESTED,
  HUMAN_ATTENTION_RESOLVED,
  createMoshiAttentionClient,
  createMoshiEnvelopeSender,
  installHumanAttention,
} from "../dot_pi/agent/extensions/human-attention.ts";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((settle) => {
    resolve = settle;
  });
  return { promise, resolve };
}

function createHarness() {
  const handlers = new Map<string, Array<(event: unknown, ctx: any) => unknown>>();
  const eventHandlers = new Map<string, Array<(data: unknown) => void>>();
  const events: Array<{ name: string; data: any }> = [];
  const pi = {
    events: {
      emit(name: string, data: unknown) {
        events.push({ name, data });
        for (const handler of eventHandlers.get(name) ?? []) handler(data);
      },
      on(name: string, handler: (data: unknown) => void) {
        const existing = eventHandlers.get(name) ?? [];
        existing.push(handler);
        eventHandlers.set(name, existing);
        return () => {
          eventHandlers.set(name, (eventHandlers.get(name) ?? []).filter((item) => item !== handler));
        };
      },
    },
    on(name: string, handler: (event: unknown, ctx: any) => unknown) {
      const existing = handlers.get(name) ?? [];
      existing.push(handler);
      handlers.set(name, existing);
    },
  };
  return { pi, handlers, events };
}

test("blocking Pi UI publishes one human-attention lifecycle", async () => {
  const harness = createHarness();
  const selected = deferred<string | undefined>();
  const ui = {
    select: async (..._args: unknown[]) => selected.promise,
  };

  installHumanAttention(harness.pi as any, { moshi: false });
  await harness.handlers.get("session_start")?.[0]({}, { ui });

  const answer = ui.select("Choose an option", ["Alpha", "Beta"]);
  const requested = harness.events.find((event) => event.name === HUMAN_ATTENTION_REQUESTED);
  assert.ok(requested);
  assert.equal(requested.data.kind, "select");
  assert.equal(requested.data.title, "Choose an option");

  selected.resolve("Alpha");
  assert.equal(await answer, "Alpha");
  const resolved = harness.events.find((event) => event.name === HUMAN_ATTENTION_RESOLVED);
  assert.ok(resolved);
  assert.equal(resolved.data.id, requested.data.id);
});

test("Herdr receives attention state without owning the lifecycle interface", async () => {
  const harness = createHarness();
  const selected = deferred<string | undefined>();
  const ui = { select: async (..._args: unknown[]) => selected.promise };

  installHumanAttention(harness.pi as any, { moshi: false });
  await harness.handlers.get("session_start")?.[0]({}, { ui });

  const answer = ui.select("Deploy where?", ["Staging", "Production"]);
  assert.deepEqual(harness.events.at(-1), {
    name: "herdr:blocked",
    data: { active: true, label: "Deploy where?" },
  });

  selected.resolve("Staging");
  await answer;
  assert.deepEqual(harness.events.at(-1), {
    name: "herdr:blocked",
    data: { active: false },
  });
});

test("Moshi receives the same attention lifecycle with prompt context", async () => {
  const harness = createHarness();
  const selected = deferred<string | undefined>();
  const calls: Array<{ phase: string; request: any }> = [];
  const moshi = {
    requestAttention(request: any) {
      calls.push({ phase: "requested", request });
    },
    resolveAttention(request: any) {
      calls.push({ phase: "resolved", request });
    },
  };
  const ui = { select: async (..._args: unknown[]) => selected.promise };

  installHumanAttention(harness.pi as any, { moshi });
  await harness.handlers.get("session_start")?.[0]({}, { ui });

  const answer = ui.select("Choose a database", ["Postgres", "SQLite"]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].phase, "requested");
  assert.equal(calls[0].request.title, "Choose a database");

  selected.resolve("Postgres");
  await answer;
  assert.equal(calls.length, 2);
  assert.equal(calls[1].phase, "resolved");
  assert.equal(calls[1].request.id, calls[0].request.id);
});

test("user-initiated workflows can suppress Moshi while retaining Herdr wait state", async () => {
  const harness = createHarness();
  const first = deferred<string | undefined>();
  const second = deferred<string | undefined>();
  let invocation = 0;
  const ui = {
    select: async (..._args: unknown[]) => (invocation++ === 0 ? first.promise : second.promise),
  };
  const calls: string[] = [];
  const moshi = {
    requestAttention() { calls.push("requested"); },
    resolveAttention() { calls.push("resolved"); },
  };

  installHumanAttention(harness.pi as any, { moshi });
  await harness.handlers.get("session_start")?.[0]({}, { ui });
  harness.pi.events.emit(HUMAN_ATTENTION_NOTIFICATIONS_SUPPRESSED, { active: true });

  const suppressedAnswer = ui.select("Feedback response", ["Latest", "Earlier"]);
  assert.deepEqual(calls, []);
  assert.deepEqual(harness.events.at(-1), {
    name: "herdr:blocked",
    data: { active: true, label: "Feedback response" },
  });
  first.resolve("Earlier");
  await suppressedAnswer;
  assert.deepEqual(calls, []);

  harness.pi.events.emit(HUMAN_ATTENTION_NOTIFICATIONS_SUPPRESSED, { active: false });
  const normalAnswer = ui.select("Agent question", ["Yes", "No"]);
  assert.deepEqual(calls, ["requested"]);
  second.resolve("Yes");
  await normalAnswer;
  assert.deepEqual(calls, ["requested", "resolved"]);
});

test("the Moshi adapter maps a question wait to terminal input without approval controls", async () => {
  const payloads: any[] = [];
  const moshi = createMoshiAttentionClient((payload) => {
    payloads.push(payload);
  });
  const request = {
    id: "attention-123",
    kind: "confirm" as const,
    title: "Allow production deployment?",
  };
  const ctx = {
    cwd: "/repo/project",
    model: { id: "gpt-test" },
    sessionManager: {
      getSessionId: () => "session-456",
      getSessionFile: () => "/tmp/session-456.jsonl",
    },
    getContextUsage: () => ({ percent: 25 }),
  };

  await moshi.requestAttention(request, ctx);
  await moshi.resolveAttention(request, ctx);

  assert.equal(payloads.length, 2, "resolution updates the inbox row without another prompt");
  assert.equal(payloads[0].type, "session.update");
  assert.equal(payloads[0].source, "pi");
  assert.equal(payloads[0].sessionId, "session-456");
  assert.equal(payloads[0].category, "approval_required");
  assert.equal(payloads[0].title, "Pi needs input");
  assert.equal(payloads[0].subtitle, "Answer in terminal");
  assert.equal(payloads[0].message, "Allow production deployment?");
  assert.equal(payloads[0].contextRemaining, 75);
  assert.equal("actionId" in payloads[0], false, "questions must not render approval buttons");
  assert.equal("phase" in payloads[0], false, "questions are not approval round trips");
  assert.equal(payloads[1].eventName, HUMAN_ATTENTION_RESOLVED);
  assert.equal(payloads[1].category, "");
  assert.equal(payloads[1].title, "");
  assert.equal("actionId" in payloads[1], false);
});

test("the Moshi envelope sender writes one fire-and-forget socket message", () => {
  const connections: unknown[] = [];
  const writes: string[] = [];
  let ended = 0;
  const createConnection = (options: unknown) => {
    connections.push(options);
    return {
      setNoDelay() {},
      once(event: string, callback: () => void) {
        if (event === "connect") callback();
      },
      on() {},
      write(value: string) {
        writes.push(value);
      },
      end() {
        ended += 1;
      },
      destroy() {},
    };
  };
  const send = createMoshiEnvelopeSender(createConnection as any, "/tmp/moshi-test.sock");

  send({ type: "session.update", message: "Choose one" });

  assert.deepEqual(connections, [{ path: "/tmp/moshi-test.sock" }]);
  assert.deepEqual(JSON.parse(writes[0]), {
    type: "session.update",
    message: "Choose one",
  });
  assert.equal(writes[0].endsWith("\n"), true);
  assert.equal(ended, 1);
});

test("overlapping dialogs coalesce into one attention request", async () => {
  const harness = createHarness();
  const first = deferred<string | undefined>();
  const second = deferred<string | undefined>();
  let call = 0;
  const ui = {
    select: async (..._args: unknown[]) => (++call === 1 ? first.promise : second.promise),
  };
  const moshiRequests: any[] = [];
  const moshi = {
    requestAttention(request: any) {
      moshiRequests.push(request);
    },
    resolveAttention() {},
  };

  installHumanAttention(harness.pi as any, { moshi });
  await harness.handlers.get("session_start")?.[0]({}, { ui });

  const one = ui.select("First question", ["A"]);
  const two = ui.select("Second question", ["B"]);
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_REQUESTED).length,
    1,
  );
  assert.equal(moshiRequests.length, 1);

  first.resolve("A");
  await one;
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_RESOLVED).length,
    0,
  );

  second.resolve("B");
  await two;
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_RESOLVED).length,
    1,
  );
});

test("session shutdown clears attention and removes wrappers exactly once", async () => {
  const harness = createHarness();
  const selected = deferred<string | undefined>();
  const ui = { select: async (..._args: unknown[]) => selected.promise };

  installHumanAttention(harness.pi as any, { moshi: false });
  await harness.handlers.get("session_start")?.[0]({}, { ui });
  const pending = ui.select("Still waiting", ["Continue"]);

  await harness.handlers.get("session_shutdown")?.[0]({}, { ui });
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_RESOLVED).length,
    1,
  );
  assert.deepEqual(harness.events.at(-1), {
    name: "herdr:blocked",
    data: { active: false },
  });

  selected.resolve("Continue");
  await pending;
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_RESOLVED).length,
    1,
    "the dismissed wrapper cannot resolve the same request twice",
  );

  await ui.select("After shutdown", ["Continue"]);
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_REQUESTED).length,
    1,
    "the restored UI method is not wrapped",
  );
});

test("dialog failures still resolve attention and allow the next prompt", async () => {
  const harness = createHarness();
  let shouldFail = true;
  const ui = {
    confirm: async (..._args: unknown[]) => {
      if (shouldFail) throw new Error("dialog failed");
      return true;
    },
  };

  installHumanAttention(harness.pi as any, { moshi: false });
  await harness.handlers.get("session_start")?.[0]({}, { ui });

  await assert.rejects(ui.confirm("First prompt", "message"), /dialog failed/);
  shouldFail = false;
  assert.equal(await ui.confirm("Second prompt", "message"), true);

  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_REQUESTED).length,
    2,
  );
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_RESOLVED).length,
    2,
  );
});

test("every blocking Pi UI primitive publishes attention", async () => {
  const harness = createHarness();
  const ui = {
    select: async (..._args: unknown[]) => "Alpha",
    confirm: async (..._args: unknown[]) => true,
    input: async (..._args: unknown[]) => "typed",
    editor: async (..._args: unknown[]) => "edited",
    custom: async (..._args: unknown[]) => "custom",
  };

  installHumanAttention(harness.pi as any, { moshi: false });
  await harness.handlers.get("session_start")?.[0]({}, { ui });

  await ui.select("Select title", []);
  await ui.confirm("Confirm title", "message");
  await ui.input("Input title");
  await ui.editor("Editor title", "prefill");
  await ui.custom(() => undefined);

  assert.deepEqual(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_REQUESTED).map((event) => [
      event.data.kind,
      event.data.title,
    ]),
    [
      ["select", "Select title"],
      ["confirm", "Confirm title"],
      ["input", "Input title"],
      ["editor", "Editor title"],
      ["custom", undefined],
    ],
  );
  assert.equal(
    harness.events.filter((event) => event.name === HUMAN_ATTENTION_RESOLVED).length,
    5,
  );
});
