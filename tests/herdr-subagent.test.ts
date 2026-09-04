import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import {
  installHerdrSubagent,
  type HerdrClient,
} from "../dot_pi/agent/extensions/herdr-subagent/index.ts";

class FakeHerdr implements HerdrClient {
  agentRunning = true;
  tabOpen = true;
  agentPresenceOverride: "present" | "absent" | "unknown" | undefined;
  tabPresenceOverride: "present" | "absent" | "unknown" | undefined;
  startError: Error | undefined;
  agentPresenceError: Error | undefined;
  createRequests: unknown[] = [];
  startRequests: unknown[] = [];
  promptRequests: unknown[] = [];
  closedTabs: string[] = [];
  focusedTabs: string[] = [];
  stoppedAgents: string[] = [];

  async createTab(request: unknown) {
    this.createRequests.push(request);
    this.tabOpen = true;
    return { tabId: "w1:t2", paneId: "w1:p2" };
  }

  async startAgent(request: unknown) {
    this.startRequests.push(request);
    if (this.startError) throw this.startError;
    this.agentRunning = true;
  }

  async getAgentPresence(_name: string) {
    if (this.agentPresenceError) throw this.agentPresenceError;
    return this.agentPresenceOverride ?? (this.agentRunning ? ("present" as const) : ("absent" as const));
  }

  async getTabPresence(_tabId: string) {
    return this.tabPresenceOverride ?? (this.tabOpen ? ("present" as const) : ("absent" as const));
  }

  async stopAgent(name: string) {
    this.stoppedAgents.push(name);
    this.agentRunning = false;
  }

  async promptAgent(request: unknown) {
    this.promptRequests.push(request);
  }

  async closeTab(tabId: string) {
    this.closedTabs.push(tabId);
    this.tabOpen = false;
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
      return [
        "read",
        "bash",
        "subagent",
        "subagent_send",
        "subagent_cancel",
        "subagent_wait",
        "subagent_close",
      ];
    },
    getAllTools() {
      return [
        "read",
        "bash",
        "subagent",
        "subagent_send",
        "subagent_cancel",
        "subagent_wait",
        "subagent_close",
      ].map((name) => ({ name }));
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
    sessionManager: {
      getSessionId() {
        return "parent-session-1";
      },
      getLeafId() {
        return "parent-entry-1";
      },
      getBranch() {
        return [{ id: "parent-entry-1" }];
      },
      getEntries() {
        return [];
      },
    },
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

test("an autonomous child completes only through finish_task", async (t) => {
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
  for (const settled of harness.handlers.get("agent_settled") ?? []) {
    await settled({}, createContext());
  }
  assert.equal(existsSync(resultFile), false, "ordinary settling is not Task completion");

  const finish = harness.tools.get("finish_task");
  assert.ok(finish, "registers explicit completion for autonomous children");
  await finish.execute(
    "call-1",
    { result: "The review found no issues." },
    undefined,
    undefined,
    {
      ...createContext(),
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
      notified: true,
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

  const duplicate = await requestAttention.execute(
    "call-2",
    { reason: "A different reason must not replace the pending request." },
    undefined,
    undefined,
    createContext(),
  );
  assert.equal(duplicate.details.reason, "Choose between the two proposed interfaces.");
  assert.equal(harness.emittedEvents.length, 1);

  const input = harness.handlers.get("input")?.[0];
  assert.ok(input, "tracks direct human input separately from parent steering");
  const parentDirection = await input(
    {
      text: "[[pi-subagent-parent:99990000111122223333444455556666]]\nKeep investigating.",
      source: "interactive",
    },
    createContext(),
  );
  assert.deepEqual(parentDirection, {
    action: "transform",
    text: "Keep investigating.",
    images: undefined,
  });
  assert.equal(JSON.parse(readFileSync(stateFile, "utf8")).status, "waiting_for_human");

  await input({ text: "Use the second interface.", source: "interactive" }, createContext());
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

test("request_attention suppresses escalation during a focused conversation", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const harness = createPiHarness();
  (harness.pi as any).exec = async () => ({
    code: 0,
    stderr: "",
    stdout: JSON.stringify({ result: { pane: { focused: true } } }),
  });

  installHerdrSubagent(harness.pi as any, {
    artifactRoot,
    env: {
      PI_HERDR_SUBAGENT: "1",
      PI_HERDR_SUBAGENT_DEPTH: "1",
      PI_HERDR_SUBAGENT_INTERACTIVE: "1",
      PI_HERDR_SUBAGENT_RESULT_FILE: join(artifactRoot, "result.json"),
      PI_HERDR_SUBAGENT_STATE_FILE: join(artifactRoot, "state.json"),
      PI_HERDR_SUBAGENT_TOKEN: "abababababababababababababababab",
    },
  });

  const result = await harness.tools.get("request_attention").execute(
    "call-1",
    { reason: "Choose the contract shape." },
    undefined,
    undefined,
    createContext(),
  );

  assert.deepEqual(result.details, {
    status: "working",
    reason: "Choose the contract shape.",
    notified: false,
  });
  assert.deepEqual(harness.emittedEvents, []);
  assert.equal(existsSync(join(artifactRoot, "state.json")), false);
});

test("a child that quits before completion remains resumable", async (t) => {
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

  assert.equal(existsSync(resultFile), false);
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
  const guidelines = tool.promptGuidelines.join("\n");
  assert.match(guidelines, /subagent_wait for every child/i);
  assert.match(guidelines, /subagent_send to steer/i);
  assert.match(guidelines, /subagent_cancel/i);
  assert.match(guidelines, /pass its absolute path as subagent cwd/i);

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
    label: "Auth spec review",
    paneId: "w1:p2",
    sessionId: result.details.id,
    model: "openai-codex-personal/gpt-5.6-sol",
    thinking: "high",
    tools: ["read", "bash", "finish_task", "request_attention"],
    systemPrompt: startRequest.systemPrompt,
  });
  assert.match(startRequest.systemPrompt, /finish_task only after the entire assignment is complete/i);
  assert.match(startRequest.systemPrompt, /answering a human follow-up/i);
  assert.match(startRequest.systemPrompt, /assigned cwd as the primary checkout/i);
  assert.match(startRequest.systemPrompt, /access other repositories or use additional worktrees/i);
  assert.deepEqual(
    herdr.promptRequests.map(({ name, task }: any) => ({ name, task })),
    [{ name: startRequest.name, task: "Review the authentication change." }],
  );
});

test("subagent launches in an explicitly selected existing checkout", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const targetCwd = mkdtempSync(join(tmpdir(), "herdr-subagent-cwd-"));
  t.after(() => rmSync(targetCwd, { recursive: true, force: true }));
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
    { name: "Existing checkout", task: "Work in the assigned checkout.", cwd: targetCwd },
    undefined,
    undefined,
    createContext(),
  );

  assert.equal((herdr.createRequests[0] as any).cwd, targetCwd);
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
    livenessIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools.get("subagent").execute(
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

  await harness.tools.get("subagent_send").execute(
    "call-2",
    { id: started.details.id, message: "Keep investigating while the decision is pending." },
    undefined,
    undefined,
    createContext(widgets),
  );
  assert.deepEqual(widgets.at(-1), {
    id: "herdr-subagents",
    value: ["Subagents", "• Interactive design — waiting for human"],
    options: undefined,
  });

  herdr.agentRunning = false;
  await waitFor(() => (widgets.at(-1) as any)?.value?.[1] === "• Interactive design — interrupted");
  await harness.tools.get("subagent_send").execute(
    "call-3",
    { id: started.details.id, message: "Resume without clearing the pending decision." },
    undefined,
    undefined,
    createContext(widgets),
  );
  assert.deepEqual((widgets.at(-1) as any).value, [
    "Subagents",
    "• Interactive design — waiting for human",
  ]);
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
  assert.equal(start.includes("--no-session"), false);
  assert.ok(start.includes("--session-id"));
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
  assert.deepEqual(request.tools, ["read", "finish_task", "request_attention"]);
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

test("a failed launch remains visible when its recovery probe also fails", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  herdr.agentRunning = false;
  herdr.startError = new Error("start failed");
  herdr.agentPresenceError = new Error("presence probe failed");
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    livenessIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });

  let launchError: Error | undefined;
  try {
    await harness.tools.get("subagent").execute(
      "call-1",
      { name: "Recoverable launch", task: "Remain discoverable after launch failure." },
      undefined,
      undefined,
      createContext(),
    );
  } catch (error) {
    launchError = error as Error;
  }

  const taskIds = readdirSync(artifactRoot);
  assert.equal(taskIds.length, 1);
  assert.match(launchError?.message ?? "", new RegExp(`Task ID: ${taskIds[0]}`));
  herdr.agentPresenceError = undefined;

  const result = await harness.tools.get("subagent_wait").execute(
    "call-2",
    { id: taskIds[0] },
    undefined,
    undefined,
    createContext(),
  );
  assert.equal(result.details.status, "interrupted");
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

test("subagent_send steers a running child without completing its Task", async (t) => {
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
    { name: "Steerable review", task: "Review the first design." },
    undefined,
    undefined,
    createContext(),
  );

  const result = await harness.tools.get("subagent_send").execute(
    "call-2",
    { id: started.details.id, message: "Compare it with the second design too." },
    undefined,
    undefined,
    createContext(),
  );

  assert.match(result.content[0].text, /sent/i);
  assert.deepEqual(
    herdr.promptRequests.map(({ name, task }: any) => ({ name, task })),
    [
      { name: started.details.agentName, task: "Review the first design." },
      { name: started.details.agentName, task: "Compare it with the second design too." },
    ],
  );
});

test("subagent_send resumes an interrupted Agent conversation", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const first = createPiHarness();

  installHerdrSubagent(first.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    livenessIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await first.tools.get("subagent").execute(
    "call-1",
    { name: "Resumable review", task: "Inspect the first implementation." },
    undefined,
    undefined,
    createContext(),
  );
  herdr.agentRunning = false;
  await waitFor(() => first.messages.length === 1);
  await first.handlers.get("session_shutdown")?.[0]({ reason: "quit" }, createContext());
  herdr.tabOpen = false;

  const resumed = createPiHarness();
  installHerdrSubagent(resumed.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await resumed.handlers.get("session_start")?.[0]({ reason: "startup" }, createContext());
  await resumed.tools.get("subagent_send").execute(
    "call-2",
    { id: started.details.id, message: "Continue with the corrected implementation." },
    undefined,
    undefined,
    createContext(),
  );

  assert.equal(herdr.createRequests.length, 2, "recreates a missing retained tab");
  assert.equal(herdr.startRequests.length, 2);
  assert.equal((herdr.startRequests[1] as any).sessionId, started.details.id);
  const resumedPrompt = herdr.promptRequests.at(-1) as any;
  assert.deepEqual(
    { name: resumedPrompt.name, task: resumedPrompt.task },
    {
      name: started.details.agentName,
      task: "Continue with the corrected implementation.",
    },
  );
});

test("a hard-stopped child becomes resumably interrupted instead of hanging subagent_wait", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    livenessIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Interrupted review", task: "Review until stopped." },
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
  let waitResolved = false;
  void waiting.then(() => {
    waitResolved = true;
  });
  herdr.agentPresenceOverride = "unknown";
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(waitResolved, false, "transient Herdr errors do not interrupt a live Task");
  herdr.agentPresenceOverride = "absent";

  const result = await waiting;
  assert.equal(result.details.status, "interrupted");
  assert.match(result.content[0].text, /can be resumed with subagent_send/i);
});

test("a resumed parent session recovers ownership of an active Task", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const first = createPiHarness();

  installHerdrSubagent(first.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await first.tools.get("subagent").execute(
    "call-1",
    { name: "Durable review", task: "Review the durable lifecycle." },
    undefined,
    undefined,
    createContext(),
  );
  await first.handlers.get("session_shutdown")?.[0]({ reason: "quit" }, createContext());

  const resumed = createPiHarness();
  installHerdrSubagent(resumed.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await resumed.handlers.get("session_start")?.[0]({ reason: "startup" }, createContext());

  const waiting = resumed.tools.get("subagent_wait").execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  const createRequest = herdr.createRequests[0] as any;
  writeFileSync(
    createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "Recovered after the parent restart.",
    }),
  );

  const result = await waiting;
  assert.match(result.content[0].text, /Recovered after the parent restart/);
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

test("subagent_cancel stops an active child and leaves terminal cleanup explicit", async (t) => {
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
    { name: "Cancelled review", task: "Review until cancelled." },
    undefined,
    undefined,
    createContext(),
  );

  const cancelled = await harness.tools.get("subagent_cancel").execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  assert.equal(cancelled.details.status, "cancelled");
  assert.deepEqual(herdr.stoppedAgents, [started.details.agentName]);
  assert.deepEqual(herdr.closedTabs, []);

  await harness.tools.get("subagent_close").execute(
    "call-3",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  assert.deepEqual(herdr.closedTabs, ["w1:t2"]);
  assert.equal(existsSync(join(artifactRoot, started.details.id)), false);
});

test("lifecycle transitions reject concurrent send and cancel operations", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  let releaseStop: (() => void) | undefined;
  herdr.stopAgent = async (name: string) => {
    herdr.stoppedAgents.push(name);
    await new Promise<void>((resolve) => {
      releaseStop = resolve;
    });
    herdr.agentRunning = false;
  };
  const harness = createPiHarness();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Serialized lifecycle", task: "Wait for lifecycle operations." },
    undefined,
    undefined,
    createContext(),
  );
  const cancelling = harness.tools.get("subagent_cancel").execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  await waitFor(() => releaseStop !== undefined);

  await assert.rejects(
    harness.tools.get("subagent_send").execute(
      "call-3",
      { id: started.details.id, message: "This must not race cancellation." },
      undefined,
      undefined,
      createContext(),
    ),
    /already changing state/i,
  );
  releaseStop?.();
  await cancelling;
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
    content: [{ type: "text", text: "Closed subagent Task Closable design." }],
    details: { id: started.details.id, name: "Closable design", status: "closed" },
  });
  assert.deepEqual(herdr.closedTabs, ["w1:t2"]);
  assert.equal(existsSync(dirname(resultFile)), false);
});

test("subagent_close retains ownership when Herdr tab state is indeterminate", async (t) => {
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
    { name: "Uncertain close", task: "Complete for uncertain cleanup.", interactive: true },
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
  writeFileSync(
    createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "Ready for close.",
    }),
  );
  await waiting;
  herdr.tabPresenceOverride = "unknown";

  await assert.rejects(
    harness.tools.get("subagent_close").execute(
      "call-3",
      { id: started.details.id },
      undefined,
      undefined,
      createContext(),
    ),
    /Could not verify/i,
  );
  assert.equal(existsSync(join(artifactRoot, started.details.id)), true);
  herdr.tabPresenceOverride = "present";
  await harness.tools.get("subagent_close").execute(
    "call-4",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
});

test("parent restart preserves terminal cleanup policy", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const first = createPiHarness();

  installHerdrSubagent(first.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await first.tools.get("subagent").execute(
    "call-1",
    { name: "Restart cleanup", task: "Complete for cleanup.", interactive: true },
    undefined,
    undefined,
    createContext(),
  );
  const waiting = first.tools.get("subagent_wait").execute(
    "call-2",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );
  const createRequest = herdr.createRequests[0] as any;
  writeFileSync(
    createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "Small terminal result.",
    }),
  );
  await waiting;
  await first.handlers.get("session_shutdown")?.[0]({ reason: "quit" }, createContext());

  const resumed = createPiHarness();
  installHerdrSubagent(resumed.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await resumed.handlers.get("session_start")?.[0]({ reason: "startup" }, createContext());
  await resumed.tools.get("subagent_close").execute(
    "call-3",
    { id: started.details.id },
    undefined,
    undefined,
    createContext(),
  );

  assert.equal(existsSync(join(artifactRoot, started.details.id)), false);
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

test("an unclaimed interruption waits for the parent conversation branch that launched it", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();
  const ctx = createContext();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    livenessIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Branch-owned interruption", task: "Stop on another branch." },
    undefined,
    undefined,
    ctx,
  );
  ctx.sessionManager.getBranch = () => [{ id: "different-parent-entry" }];
  herdr.agentRunning = false;

  await waitFor(() => {
    const [taskId] = readdirSync(artifactRoot);
    if (!taskId) return false;
    const manifest = JSON.parse(readFileSync(join(artifactRoot, taskId, "task.json"), "utf8"));
    return manifest.status === "interrupted";
  });
  assert.deepEqual(harness.messages, []);

  ctx.sessionManager.getBranch = () => [{ id: "parent-entry-1" }];
  await harness.handlers.get("session_tree")?.[0]({}, ctx);
  assert.equal(harness.messages.length, 1);
  assert.match((harness.messages[0] as any).message.content, /can be resumed with subagent_send/i);

  await harness.handlers.get("session_tree")?.[0]({}, ctx);
  assert.equal(harness.messages.length, 1, "delivers the interruption notice only once");
});

test("an unclaimed Result waits for the parent conversation branch that launched it", async (t) => {
  const artifactRoot = mkdtempSync(join(tmpdir(), "herdr-subagent-test-"));
  t.after(() => rmSync(artifactRoot, { recursive: true, force: true }));
  const herdr = new FakeHerdr();
  const harness = createPiHarness();
  const ctx = createContext();

  installHerdrSubagent(harness.pi as any, {
    herdr,
    artifactRoot,
    pollIntervalMs: 5,
    env: { HERDR_ENV: "1", HERDR_WORKSPACE_ID: "w1" },
  });
  const started = await harness.tools.get("subagent").execute(
    "call-1",
    { name: "Branch-owned result", task: "Return to the launch branch." },
    undefined,
    undefined,
    ctx,
  );
  ctx.sessionManager.getBranch = () => [{ id: "different-parent-entry" }];

  const createRequest = herdr.createRequests[0] as any;
  writeFileSync(
    createRequest.env.PI_HERDR_SUBAGENT_RESULT_FILE,
    JSON.stringify({
      schemaVersion: 1,
      token: createRequest.env.PI_HERDR_SUBAGENT_TOKEN,
      status: "completed",
      output: "Deliver only to the launch branch.",
    }),
  );
  await waitFor(() => herdr.closedTabs.length === 1);
  assert.deepEqual(harness.messages, []);
  assert.equal(existsSync(join(artifactRoot, started.details.id)), true);

  ctx.sessionManager.getBranch = () => [{ id: "parent-entry-1" }];
  await harness.handlers.get("session_tree")?.[0]({}, ctx);
  assert.equal(harness.messages.length, 1);
  assert.match((harness.messages[0] as any).message.content, /Deliver only to the launch branch/);
  assert.equal(existsSync(join(artifactRoot, started.details.id)), false);
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
  const started = await tool.execute(
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
          id: started.details.id,
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
