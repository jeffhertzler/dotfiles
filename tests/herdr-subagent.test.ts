import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import {
  installHerdrSubagent,
  type HerdrClient,
} from "../dot_pi/agent/extensions/herdr-subagent/index.ts";

class FakeHerdr implements HerdrClient {
  createRequests: unknown[] = [];
  startRequests: unknown[] = [];
  promptRequests: unknown[] = [];
  closedTabs: string[] = [];
  focusedTabs: string[] = [];

  async createTab(request: unknown) {
    this.createRequests.push(request);
    return { tabId: "w1:t2", paneId: "w1:p2" };
  }

  async startAgent(request: unknown) {
    this.startRequests.push(request);
  }

  async promptAgent(request: unknown) {
    this.promptRequests.push(request);
  }

  async closeTab(tabId: string) {
    this.closedTabs.push(tabId);
  }

  async focusTab(tabId: string) {
    this.focusedTabs.push(tabId);
  }

}

function createPiHarness() {
  const tools = new Map<string, any>();
  const commands = new Map<string, any>();
  const handlers = new Map<string, Array<(event: any, ctx: any) => unknown>>();
  const messages: unknown[] = [];
  const emittedEvents: unknown[] = [];
  const pi = {
    events: {
      emit(name: string, data: unknown) {
        emittedEvents.push({ name, data });
      },
    },
    registerTool(tool: any) {
      tools.set(tool.name, tool);
    },
    registerCommand(name: string, command: any) {
      commands.set(name, command);
    },
    on(event: string, handler: (event: any, ctx: any) => unknown) {
      const registered = handlers.get(event) ?? [];
      registered.push(handler);
      handlers.set(event, registered);
    },
    getActiveTools() {
      return ["read", "bash", "subagent", "subagent_wait", "subagent_close"];
    },
    getAllTools() {
      return ["read", "bash", "subagent", "subagent_wait", "subagent_close"].map((name) => ({
        name,
      }));
    },
    sendMessage(message: unknown, options: unknown) {
      messages.push({ message, options });
    },
  };
  return { pi, tools, commands, handlers, messages, emittedEvents };
}

async function waitFor(predicate: () => boolean, timeoutMs = 500): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("Timed out waiting for condition");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function createContext(widgets: unknown[] = []) {
  return {
    cwd: "/repo/task-worktree",
    model: { provider: "openai-codex-personal", id: "gpt-5.6-sol" },
    thinkingLevel: "high",
    modelRegistry: {
      find(provider: string, model: string) {
        return provider === "openai-codex-personal" && model === "gpt-5.6-sol"
          ? { provider, id: model }
          : undefined;
      },
    },
    ui: {
      setWidget(id: string, value: unknown, options?: unknown) {
        widgets.push({ id, value, options });
      },
    },
  };
}

test("a child publishes its final answer without exposing another subagent tool", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const resultFile = join(artifactRoot, "result.json");
  const harness = createPiHarness();
  let shutdowns = 0;

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    env: {
      HERDR_ENV: "1",
      HERDR_WORKSPACE_ID: "w1",
      PI_HERDR_SUBAGENT: "1",
      PI_HERDR_SUBAGENT_DEPTH: "1",
      PI_HERDR_SUBAGENT_RESULT_FILE: resultFile,
      PI_HERDR_SUBAGENT_TOKEN: "0123456789abcdef0123456789abcdef",
    },
  });

  assert.equal(harness.tools.has("subagent"), false);
  assert.equal(harness.tools.has("subagent_wait"), false);
  const settled = harness.handlers.get("agent_settled")?.[0];
  assert.ok(settled, "registers child completion handling");
  await settled(
    {},
    {
      sessionManager: {
        getBranch() {
          return [
            {
              type: "message",
              message: {
                role: "assistant",
                content: [{ type: "text", text: "The review found no issues." }],
                stopReason: "end",
              },
            },
          ];
        },
      },
      shutdown() {
        shutdowns += 1;
      },
    },
  );

  assert.deepEqual(JSON.parse(readFileSync(resultFile, "utf8")), {
    schemaVersion: 1,
    token: "0123456789abcdef0123456789abcdef",
    status: "completed",
    output: "The review found no issues.",
  });
  assert.equal(shutdowns, 1);
});

test("an interactive child stays available until finish_task explicitly completes its Task", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const resultFile = join(artifactRoot, "result.json");
  const harness = createPiHarness();
  let shutdowns = 0;

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    env: {
      PI_HERDR_SUBAGENT: "1",
      PI_HERDR_SUBAGENT_DEPTH: "1",
      PI_HERDR_SUBAGENT_INTERACTIVE: "1",
      PI_HERDR_SUBAGENT_RESULT_FILE: resultFile,
      PI_HERDR_SUBAGENT_TOKEN: "11112222333344445555666677778888",
    },
  });

  for (const settled of harness.handlers.get("agent_settled") ?? []) {
    await settled({}, {
      sessionManager: {
        getBranch: () => [
          {
            type: "message",
            message: {
              role: "assistant",
              content: [{ type: "text", text: "What would you like to adjust?" }],
              stopReason: "end",
            },
          },
        ],
      },
      shutdown: () => {
        shutdowns += 1;
      },
    });
  }
  assert.equal(existsSync(resultFile), false);
  assert.equal(shutdowns, 0);

  const finish = harness.tools.get("finish_task");
  assert.ok(finish, "registers the child-only completion tool");
  const finished = await finish.execute(
    "call-1",
    { result: "The human-approved design is ready." },
    undefined,
    undefined,
    createContext(),
  );

  assert.deepEqual(finished, {
    content: [{ type: "text", text: "Task completed and its result was returned to the parent." }],
    details: { status: "completed" },
  });
  assert.deepEqual(JSON.parse(readFileSync(resultFile, "utf8")), {
    schemaVersion: 1,
    token: "11112222333344445555666677778888",
    status: "completed",
    output: "The human-approved design is ready.",
  });
  assert.equal(shutdowns, 0);
  assert.equal(harness.tools.has("subagent"), false);
  assert.equal(harness.tools.has("subagent_wait"), false);
});

test("a human can use /finish to return the last interactive response", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const resultFile = join(artifactRoot, "result.json");
  const harness = createPiHarness();
  const notifications: unknown[] = [];

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    env: {
      PI_HERDR_SUBAGENT: "1",
      PI_HERDR_SUBAGENT_DEPTH: "1",
      PI_HERDR_SUBAGENT_INTERACTIVE: "1",
      PI_HERDR_SUBAGENT_RESULT_FILE: resultFile,
      PI_HERDR_SUBAGENT_TOKEN: "aaaabbbbccccddddeeeeffff00001111",
    },
  });

  const finish = harness.commands.get("finish");
  assert.ok(finish, "registers the human-facing finish command");
  await finish.handler("", {
    sessionManager: {
      getBranch: () => [
        {
          type: "message",
          message: {
            role: "assistant",
            content: [{ type: "text", text: "Use the second interface." }],
            stopReason: "end",
          },
        },
      ],
    },
    ui: {
      notify(message: string, level: string) {
        notifications.push({ message, level });
      },
    },
  });

  assert.deepEqual(JSON.parse(readFileSync(resultFile, "utf8")), {
    schemaVersion: 1,
    token: "aaaabbbbccccddddeeeeffff00001111",
    status: "completed",
    output: "Use the second interface.",
  });
  assert.deepEqual(notifications, [
    { message: "Task completed and returned to the parent", level: "info" },
  ]);
});

test("request_attention explicitly marks an interactive Task as waiting for human input", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const harness = createPiHarness();
  const resultFile = join(artifactRoot, "result.json");
  const stateFile = join(artifactRoot, "state.json");

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    env: {
      PI_HERDR_SUBAGENT: "1",
      PI_HERDR_SUBAGENT_DEPTH: "1",
      PI_HERDR_SUBAGENT_INTERACTIVE: "1",
      PI_HERDR_SUBAGENT_RESULT_FILE: resultFile,
      PI_HERDR_SUBAGENT_STATE_FILE: stateFile,
      PI_HERDR_SUBAGENT_TOKEN: "99990000111122223333444455556666",
    },
  });

  const requestAttention = harness.tools.get("request_attention");
  assert.ok(requestAttention, "registers the child-only attention tool");
  const result = await requestAttention.execute(
    "call-1",
    { reason: "Choose between the two proposed interfaces." },
    undefined,
    undefined,
    createContext(),
  );

  assert.deepEqual(result, {
    content: [{ type: "text", text: "Human attention requested. The Task remains active." }],
    details: {
      status: "waiting_for_human",
      reason: "Choose between the two proposed interfaces.",
    },
  });
  assert.deepEqual(harness.emittedEvents, [
    {
      name: "herdr:blocked",
      data: { active: true, label: "Choose between the two proposed interfaces." },
    },
  ]);
  assert.deepEqual(JSON.parse(readFileSync(stateFile, "utf8")), {
    schemaVersion: 1,
    token: "99990000111122223333444455556666",
    revision: 1,
    status: "waiting_for_human",
    reason: "Choose between the two proposed interfaces.",
  });
  assert.equal(existsSync(resultFile), false);

  for (const started of harness.handlers.get("agent_start") ?? []) await started({}, createContext());
  assert.deepEqual(harness.emittedEvents.at(-1), {
    name: "herdr:blocked",
    data: { active: false, label: "Choose between the two proposed interfaces." },
  });
  assert.deepEqual(JSON.parse(readFileSync(stateFile, "utf8")), {
    schemaVersion: 1,
    token: "99990000111122223333444455556666",
    revision: 2,
    status: "working",
  });
});

test("a child that quits before settling reports failure for parent inspection", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const resultFile = join(artifactRoot, "result.json");
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    env: {
      PI_HERDR_SUBAGENT: "1",
      PI_HERDR_SUBAGENT_DEPTH: "1",
      PI_HERDR_SUBAGENT_RESULT_FILE: resultFile,
      PI_HERDR_SUBAGENT_TOKEN: "fedcba9876543210fedcba9876543210",
    },
  });

  const shutdown = harness.handlers.get("session_shutdown")?.[0];
  assert.ok(shutdown, "registers incomplete-child handling");
  await shutdown({ reason: "quit" }, {});

  assert.deepEqual(JSON.parse(readFileSync(resultFile, "utf8")), {
    schemaVersion: 1,
    token: "fedcba9876543210fedcba9876543210",
    status: "failed",
    output: "Subagent exited before producing a final result.",
  });
});

test("subagent starts a visible child using the parent runtime by default", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  const tool = harness.tools.get("subagent");
  assert.ok(tool, "registers the canonical subagent tool");
  assert.deepEqual(tool.promptGuidelines, [
    "For autonomous Tasks, partition work before launch: give the child an independent deliverable and reserve a different parent deliverable. While it runs, work only on the reserved parent deliverable.",
    "For direct human collaboration, set interactive true and set focus true only when the human is expected to engage immediately. Call subagent_wait instead of inspecting or waiting through raw Herdr commands.",
    "Call subagent_wait for every child whose result the response depends on. After all required waits return, synthesize the combined result once.",
    "After collecting a completed interactive Task, call subagent_close when its retained tab is no longer needed.",
  ]);

  const result = await tool.execute(
    "call-1",
    { name: "Auth spec review", task: "Review the authentication change." },
    undefined,
    undefined,
    createContext(),
  );

  assert.match(result.content[0].text, /started/i);
  assert.match(result.details.id, /^[a-f0-9-]{36}$/);
  assert.match(result.content[0].text, new RegExp(`Task ID: ${result.details.id}`));
  assert.match(result.content[0].text, /subagent_wait/);
  assert.equal(herdr.createRequests.length, 1);
  const createRequest = herdr.createRequests[0] as any;
  assert.equal(createRequest.workspaceId, "w1");
  assert.equal(createRequest.cwd, "/repo/task-worktree");
  assert.equal(createRequest.label, "Auth spec review");
  assert.equal(createRequest.env.PI_HERDR_SUBAGENT, "1");
  assert.equal(createRequest.env.PI_HERDR_SUBAGENT_DEPTH, "1");
  assert.match(createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE, /result\.json$/);
  assert.match(createRequest.env.PI_HERDR_SUBAGENT_TOKEN, /^[a-f0-9]{32}$/);
  assert.equal(herdr.startRequests.length, 1);
  const startRequest = herdr.startRequests[0] as any;
  assert.match(startRequest.name, /^auth-spec-review-[a-f0-9]{6}$/);
  assert.deepEqual(startRequest, {
    name: startRequest.name,
    paneId: "w1:p2",
    model: "openai-codex-personal/gpt-5.6-sol",
    thinking: "high",
    tools: ["read", "bash"],
    systemPrompt:
      "You are a delegated subagent. Complete the supplied task directly. Do not spawn or control other agents. If a skill says to delegate the work assigned to you, perform that work yourself instead.",
  });
  assert.deepEqual(herdr.promptRequests, [
    { name: startRequest.name, task: "Review the authentication change." },
  ]);
});

test("an interactive Task can focus its persistent child tab at launch", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  await harness.tools.get("subagent").execute(
    "call-1",
    {
      name: "Interactive design",
      task: "Work through the design with me.",
      interactive: true,
      focus: true,
    },
    undefined,
    undefined,
    createContext(),
  );

  const createRequest = herdr.createRequests[0] as any;
  assert.equal(createRequest.env.PI_HERDR_SUBAGENT_INTERACTIVE, "1");
  const startRequest = herdr.startRequests[0] as any;
  assert.deepEqual(startRequest.tools, ["read", "bash", "finish_task", "request_attention"]);
  assert.match(startRequest.systemPrompt, /remain available across turns/i);
  assert.match(startRequest.systemPrompt, /finish_task/);
  assert.deepEqual(herdr.focusedTabs, ["w1:t2"]);
});

test("request_attention updates parent Task status without changing focus", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();
  const widgets: unknown[] = [];

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Interactive design", task: "Work with me.", interactive: true },
    undefined,
    undefined,
    createContext(widgets),
  );

  const createRequest = herdr.createRequests[0] as any;
  const stateFile = createRequest.env.PI_HERDR_SUBAGENT_STATE_FILE;
  assert.match(stateFile, /state\.json$/);
  writeFileSync(
    stateFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      revision: 1,
      status: "waiting_for_human",
      reason: "Choose the public interface.",
    }),
  );

  await waitFor(
    () =>
      (widgets.at(-1) as any)?.value?.[1] === "• Interactive design — waiting for human",
  );
  assert.deepEqual(herdr.focusedTabs, []);
  assert.deepEqual(widgets.at(-1), {
    id: "herdr-subagents",
    value: ["Subagents", "• Interactive design — waiting for human"],
    options: undefined,
  });
});

test("the real adapter launches Pi through Herdr without disabling child skills", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const harness = createPiHarness();
  const commands: string[][] = [];
  let startAttempts = 0;
  (harness.pi as any).exec = async (command: string, args: string[]) => {
    assert.equal(command, "herdr");
    commands.push(args);
    if (args[0] === "tab" && args[1] === "create") {
      return {
        code: 0,
        stderr: "",
        stdout: JSON.stringify({
          result: { tab: { tab_id: "w1:t9" }, root_pane: { pane_id: "w1:p9" } },
        }),
      };
    }
    if (args[0] === "agent" && args[1] === "start" && startAttempts++ === 0) {
      return {
        code: 1,
        stdout: "",
        stderr: JSON.stringify({
          error: { code: "agent_pane_busy", message: "not an available shell" },
        }),
      };
    }
    return { code: 0, stderr: "", stdout: JSON.stringify({ result: {} }) };
  };

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await harness.tools
    .get("subagent")
    .execute(
      "call-1",
      { name: "CLI check", task: "Return OK." },
      undefined,
      undefined,
      createContext(),
    );

  assert.deepEqual(
    commands.map((args) => args.slice(0, 2)),
    [
      ["tab", "create"],
      ["agent", "start"],
      ["agent", "start"],
      ["agent", "prompt"],
    ],
  );
  const start = commands[2];
  assert.ok(start.includes("--no-session"));
  assert.ok(start.includes("--append-system-prompt"));
  assert.ok(start.includes("--tools"));
  assert.equal(start.includes("--no-skills"), false);
});

test("explicit tools, model, and thinking override parent defaults", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();
  const ctx = createContext();
  ctx.modelRegistry.find = (provider: string, model: string) =>
    provider === "anthropic" && model === "claude-sonnet" ? { provider, id: model } : undefined;

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  await harness.tools.get("subagent").execute(
    "call-1",
    {
      name: "Focused reader",
      task: "Read one file.",
      tools: ["read"],
      model: "anthropic/claude-sonnet",
      thinking: "low",
    },
    undefined,
    undefined,
    ctx,
  );

  const request = herdr.startRequests[0] as any;
  assert.equal(request.model, "anthropic/claude-sonnet");
  assert.equal(request.thinking, "low");
  assert.deepEqual(request.tools, ["read"]);
});

test("invalid runtime options fail before Herdr resources are created", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  await assert.rejects(
    harness.tools
      .get("subagent")
      .execute(
        "call-1",
        { name: "Invalid", task: "Do work.", tools: ["not-a-tool"] },
        undefined,
        undefined,
        createContext(),
      ),
    /Unknown subagent tools: not-a-tool/,
  );
  assert.deepEqual(herdr.createRequests, []);
});

test("concurrent children with the same display name receive unique Herdr names", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  const tool = harness.tools.get("subagent");
  await tool.execute(
    "call-1",
    { name: "Review", task: "Review A." },
    undefined,
    undefined,
    createContext(),
  );
  await tool.execute(
    "call-2",
    { name: "Review", task: "Review B." },
    undefined,
    undefined,
    createContext(),
  );

  const names = herdr.startRequests.map((request: any) => request.name);
  assert.equal(new Set(names).size, 2);
  assert.ok(names.every((name) => /^review-[a-f0-9]{6}$/.test(name)));
});

test("active children are visible until the parent session shuts down", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();
  const widgets: unknown[] = [];

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  await harness.tools
    .get("subagent")
    .execute(
      "call-1",
      { name: "Architecture scan", task: "Map the current architecture." },
      undefined,
      undefined,
      createContext(widgets),
    );

  assert.deepEqual(widgets.at(-1), {
    id: "herdr-subagents",
    value: ["Subagents", "• Architecture scan — working"],
    options: undefined,
  });

  const shutdown = harness.handlers.get("session_shutdown")?.[0];
  assert.ok(shutdown);
  await shutdown({}, createContext(widgets));
  assert.deepEqual(widgets.at(-1), {
    id: "herdr-subagents",
    value: undefined,
    options: undefined,
  });
});

test("subagent_wait claims a Task and returns its result without automatic redelivery", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  const started = await harness.tools
    .get("subagent")
    .execute(
      "call-1",
      { name: "Joined review", task: "Review the change." },
      undefined,
      undefined,
      createContext(),
    );
  const waitTool = harness.tools.get("subagent_wait");
  assert.ok(waitTool, "registers the result collection tool");
  const waiting = waitTool.execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );

  const createRequest = herdr.createRequests[0] as any;
  const resultFile = createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE;
  writeFileSync(
    resultFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "The joined review passed.",
    }),
  );

  const result = await waiting;
  assert.deepEqual(result, {
    content: [
      {
        type: "text",
        text: "Subagent Joined review completed:\n\nThe joined review passed.",
      },
    ],
    details: {
      id: started.details.id,
      name: "Joined review",
      status: "completed",
      tabId: "w1:t2",
    },
  });
  assert.deepEqual(harness.messages, []);
  assert.deepEqual(herdr.closedTabs, ["w1:t2"]);
  assert.equal(existsSync(dirname(resultFile)), false);
});

test("finishing an interactive Task returns its result without closing the child tab", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Interactive review", task: "Review this with me.", interactive: true },
    undefined,
    undefined,
    createContext(),
  );
  const waiting = harness.tools.get("subagent_wait").execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  const createRequest = herdr.createRequests[0] as any;
  const resultFile = createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE;
  writeFileSync(
    resultFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "The interactive review is complete.",
    }),
  );

  const result = await waiting;
  assert.match(result.content[0].text, /interactive review is complete/i);
  assert.deepEqual(herdr.closedTabs, []);
  assert.equal(existsSync(dirname(resultFile)), true);
});

test("subagent_close explicitly closes a completed interactive Task", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Closable design", task: "Work with me.", interactive: true },
    undefined,
    undefined,
    createContext(),
  );
  const waiting = harness.tools.get("subagent_wait").execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  const createRequest = herdr.createRequests[0] as any;
  const resultFile = createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE;
  writeFileSync(
    resultFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "Ready to close.",
    }),
  );
  await waiting;

  const close = harness.tools.get("subagent_close");
  assert.ok(close, "registers explicit interactive cleanup");
  const result = await close.execute(
    "call-3",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );

  assert.deepEqual(result, {
    content: [{ type: "text", text: "Closed interactive Task Closable design." }],
    details: { id: started.details.id, name: "Closable design", status: "closed" },
  });
  assert.deepEqual(herdr.closedTabs, ["w1:t2"]);
  assert.equal(existsSync(dirname(resultFile)), false);
});

test("aborting subagent_wait releases the Task for automatic delivery", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools
    .get("subagent")
    .execute(
      "call-1",
      { name: "Released review", task: "Review the change." },
      undefined,
      undefined,
      createContext(),
    );
  const controller = new AbortController();
  const waiting = harness.tools
    .get("subagent_wait")
    .execute("call-2", { id: started.details.id }, controller.signal, undefined, createContext());
  controller.abort();

  const createRequest = herdr.createRequests[0] as any;
  writeFileSync(
    createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "The released review passed.",
    }),
  );

  await assert.rejects(waiting, /aborted/i);
  await waitFor(() => harness.messages.length === 1);
  assert.match((harness.messages[0] as any).message.content, /The released review passed/);
});

test("a failed child is reported but its tab and artifacts are preserved", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  await harness.tools
    .get("subagent")
    .execute(
      "call-1",
      { name: "Broken review", task: "Attempt the review." },
      undefined,
      undefined,
      createContext(),
    );
  const createRequest = herdr.createRequests[0] as any;
  const resultFile = createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE;
  writeFileSync(
    resultFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "failed",
      output: "Provider request failed.",
    }),
  );

  await waitFor(() => harness.messages.length === 1);
  assert.equal((harness.messages[0] as any).message.details.status, "failed");
  assert.deepEqual(herdr.closedTabs, []);
  assert.equal(existsSync(dirname(resultFile)), true);
});

test("large results are bounded in parent context and retained on disk", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await harness.tools
    .get("subagent")
    .execute(
      "call-1",
      { name: "Large report", task: "Produce a report." },
      undefined,
      undefined,
      createContext(),
    );
  const createRequest = herdr.createRequests[0] as any;
  const resultFile = createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE;
  writeFileSync(
    resultFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "x".repeat(60 * 1024),
    }),
  );

  await waitFor(() => harness.messages.length === 1);
  await waitFor(() => herdr.closedTabs.length === 1);
  const content = (harness.messages[0] as any).message.content as string;
  assert.ok(Buffer.byteLength(content, "utf8") < 52 * 1024);
  assert.match(content, /Output truncated/);
  assert.match(content, new RegExp(resultFile.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.equal(existsSync(dirname(resultFile)), true);
});

test("a completed child result is delivered once and its owned tab is closed", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  const tool = harness.tools.get("subagent");
  await tool.execute(
    "call-1",
    { name: "Standards review", task: "Review project standards." },
    undefined,
    undefined,
    createContext(),
  );

  const createRequest = herdr.createRequests[0] as any;
  const resultFile = createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE;
  writeFileSync(
    resultFile,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "No standards violations found.",
    }),
  );

  await waitFor(() => harness.messages.length === 1);
  await waitFor(() => herdr.closedTabs.length === 1);
  await new Promise((resolve) => setTimeout(resolve, 20));

  assert.deepEqual(harness.messages, [
    {
      message: {
        customType: "subagent_result",
        content: "Subagent Standards review completed:\n\nNo standards violations found.",
        display: true,
        details: {
          name: "Standards review",
          status: "completed",
          tabId: "w1:t2",
        },
      },
      options: { deliverAs: "followUp", triggerTurn: true },
    },
  ]);
  assert.deepEqual(herdr.closedTabs, ["w1:t2"]);
  assert.equal(existsSync(dirname(resultFile)), false);
});
