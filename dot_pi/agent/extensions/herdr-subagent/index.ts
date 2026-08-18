import { randomBytes, randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const CHILD_ENV = "PI_HERDR_SUBAGENT";
const DEPTH_ENV = "PI_HERDR_SUBAGENT_DEPTH";
const RESULT_FILE_ENV = "PI_HERDR_SUBAGENT_RESULT_FILE";
const STATE_FILE_ENV = "PI_HERDR_SUBAGENT_STATE_FILE";
const TOKEN_ENV = "PI_HERDR_SUBAGENT_TOKEN";
const INTERACTIVE_ENV = "PI_HERDR_SUBAGENT_INTERACTIVE";
const DEFAULT_MAX_DEPTH = 1;
const MAX_PARENT_OUTPUT_BYTES = 48 * 1024;
const AUTONOMOUS_CHILD_SYSTEM_PROMPT =
  "You are a delegated subagent. Complete the supplied task directly. Do not spawn or control other agents. If a skill says to delegate the work assigned to you, perform that work yourself instead.";
const INTERACTIVE_CHILD_SYSTEM_PROMPT =
  "You are working on an interactive delegated Task. Remain available across turns: becoming idle does not complete the Task. Call finish_task only when the human explicitly asks you to finish and return a result. Call request_attention when you need human input. Do not spawn or control other agents; perform delegated work yourself.";

const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;
type ThinkingLevel = (typeof THINKING_LEVELS)[number];

interface CreateTabRequest {
  workspaceId: string;
  cwd: string;
  label: string;
  env: Record<string, string>;
}

interface StartAgentRequest {
  name: string;
  paneId: string;
  model: string;
  thinking: ThinkingLevel;
  tools: string[];
  systemPrompt: string;
}

interface PromptAgentRequest {
  name: string;
  task: string;
}

interface ChildResult {
  schemaVersion: 1;
  token: string;
  status: "completed" | "failed";
  output: string;
}

interface TaskState {
  schemaVersion: 1;
  token: string;
  revision: number;
  status: "working" | "waiting_for_human";
  reason?: string;
}

interface RetainedTask {
  name: string;
  tabId: string;
  resultDirectory: string;
  retainArtifacts: boolean;
  status: "completed" | "failed";
}

interface ActiveTask {
  name: string;
  interactive: boolean;
  tabId: string;
  resultDirectory: string;
  resultFile: string;
  stateFile: string;
  stateRevision: number;
  status: "working" | "waiting_for_human";
  token: string;
  timer: ReturnType<typeof setInterval>;
  settling: boolean;
  claimed: boolean;
  resolveWait?: (result: unknown) => void;
}

export interface HerdrClient {
  createTab(request: CreateTabRequest): Promise<{ tabId: string; paneId: string }>;
  startAgent(request: StartAgentRequest): Promise<void>;
  promptAgent(request: PromptAgentRequest): Promise<void>;
  focusTab(tabId: string): Promise<void>;
  closeTab(tabId: string): Promise<void>;
}

interface ToolDefinition {
  name: string;
  [key: string]: unknown;
}

interface PiLike {
  events: { emit(name: string, data: unknown): void };
  registerTool(tool: ToolDefinition): void;
  registerCommand(name: string, command: unknown): void;
  on(event: string, handler: (event: unknown, ctx: any) => unknown): void;
  getActiveTools(): string[];
  getAllTools(): Array<{ name: string }>;
  sendMessage(message: unknown, options?: unknown): void;
  exec?(
    command: string,
    args: string[],
    options?: unknown,
  ): Promise<{
    stdout: string;
    stderr: string;
    code: number;
  }>;
}

export interface InstallOptions {
  herdr?: HerdrClient;
  artifactRoot?: string;
  pollIntervalMs?: number;
  env?: Record<string, string | undefined>;
}

function requireCommandSuccess(
  command: string,
  result: { stdout: string; stderr: string; code: number },
): string {
  if (result.code !== 0) {
    throw new Error(
      `${command} failed: ${result.stderr.trim() || result.stdout.trim() || `exit ${result.code}`}`,
    );
  }
  return result.stdout;
}

function hasHerdrErrorCode(result: { stdout: string; stderr: string }, code: string): boolean {
  try {
    const payload = JSON.parse(result.stderr || result.stdout);
    return payload?.error?.code === code;
  } catch {
    return false;
  }
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function parseHerdrResult(command: string, stdout: string): any {
  try {
    return JSON.parse(stdout).result;
  } catch (error) {
    throw new Error(`${command} returned invalid JSON`, { cause: error });
  }
}

function createHerdrClient(pi: PiLike): HerdrClient {
  if (!pi.exec) throw new Error("The subagent extension requires pi.exec");
  const exec = pi.exec.bind(pi);
  return {
    async createTab(request) {
      const args = [
        "tab",
        "create",
        "--workspace",
        request.workspaceId,
        "--cwd",
        request.cwd,
        "--label",
        request.label,
      ];
      for (const [key, value] of Object.entries(request.env)) args.push("--env", `${key}=${value}`);
      args.push("--no-focus");
      const command = "herdr tab create";
      const stdout = requireCommandSuccess(command, await exec("herdr", args));
      const result = parseHerdrResult(command, stdout);
      const tabId = result?.tab?.tab_id;
      const paneId = result?.root_pane?.pane_id;
      if (typeof tabId !== "string" || typeof paneId !== "string") {
        throw new Error(`${command} did not return a tab and root pane`);
      }
      return { tabId, paneId };
    },
    async startAgent(request) {
      const args = [
        "agent",
        "start",
        request.name,
        "--kind",
        "pi",
        "--pane",
        request.paneId,
        "--",
        "--no-session",
        "--model",
        request.model,
        "--thinking",
        request.thinking,
        "--append-system-prompt",
        request.systemPrompt,
      ];
      if (request.tools.length === 0) args.push("--no-tools");
      else args.push("--tools", request.tools.join(","));
      for (let attempt = 0; attempt < 100; attempt += 1) {
        const result = await exec("herdr", args);
        if (result.code === 0) return;
        if (!hasHerdrErrorCode(result, "agent_pane_busy") || attempt === 99) {
          requireCommandSuccess("herdr agent start", result);
        }
        await delay(100);
      }
    },
    async promptAgent(request) {
      requireCommandSuccess(
        "herdr agent prompt",
        await exec("herdr", ["agent", "prompt", request.name, request.task]),
      );
    },
    async focusTab(tabId) {
      requireCommandSuccess("herdr tab focus", await exec("herdr", ["tab", "focus", tabId]));
    },
    async closeTab(tabId) {
      requireCommandSuccess("herdr tab close", await exec("herdr", ["tab", "close", tabId]));
    },
  };
}

function slugifyName(name: string, id: string): string {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  const base = (/^[a-z]/.test(slug) ? slug : `agent-${slug || "task"}`).slice(0, 25);
  return `${base}-${id.replace(/-/g, "").slice(0, 6)}`;
}

function parseModelReference(reference: string): {
  provider: string;
  model: string;
} {
  const separator = reference.indexOf("/");
  if (separator <= 0 || separator === reference.length - 1) {
    throw new Error(`Model must be an exact provider/model-id reference: ${reference}`);
  }
  return {
    provider: reference.slice(0, separator),
    model: reference.slice(separator + 1),
  };
}

function readChildResult(path: string, token: string): ChildResult | undefined {
  if (!existsSync(path)) return undefined;
  try {
    const result = JSON.parse(readFileSync(path, "utf8")) as Partial<ChildResult>;
    if (
      result.schemaVersion !== 1 ||
      result.token !== token ||
      (result.status !== "completed" && result.status !== "failed") ||
      typeof result.output !== "string"
    ) {
      return undefined;
    }
    return result as ChildResult;
  } catch {
    return undefined;
  }
}

function readTaskState(path: string, token: string): TaskState | undefined {
  if (!existsSync(path)) return undefined;
  try {
    const state = JSON.parse(readFileSync(path, "utf8")) as Partial<TaskState>;
    if (
      state.schemaVersion !== 1 ||
      state.token !== token ||
      !Number.isInteger(state.revision) ||
      (state.status !== "working" && state.status !== "waiting_for_human") ||
      (state.status === "waiting_for_human" && typeof state.reason !== "string")
    ) {
      return undefined;
    }
    return state as TaskState;
  } catch {
    return undefined;
  }
}

function boundParentOutput(
  output: string,
  resultFile: string,
): { text: string; truncated: boolean } {
  const bytes = Buffer.from(output, "utf8");
  if (bytes.length <= MAX_PARENT_OUTPUT_BYTES) return { text: output, truncated: false };
  const prefix = bytes
    .subarray(0, MAX_PARENT_OUTPUT_BYTES)
    .toString("utf8")
    .replace(/\uFFFD$/, "");
  return {
    text: `${prefix}\n\n[Output truncated. Full result retained at ${resultFile}]`,
    truncated: true,
  };
}

function assistantResult(entries: any[]): {
  status: "completed" | "failed";
  output: string;
} {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const message = entries[index]?.type === "message" ? entries[index].message : undefined;
    if (message?.role !== "assistant" || !Array.isArray(message.content)) continue;
    const output = message.content
      .filter((part: any) => part?.type === "text" && typeof part.text === "string")
      .map((part: any) => part.text)
      .join("\n\n")
      .trim();
    const failed = message.stopReason === "error" || message.stopReason === "aborted" || !output;
    return { status: failed ? "failed" : "completed", output };
  }
  return {
    status: "failed",
    output: "No final assistant response was produced.",
  };
}

function writePrivateJson(path: string, value: unknown): void {
  const temporaryPath = `${path}.${process.pid}.tmp`;
  try {
    writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    renameSync(temporaryPath, path);
  } finally {
    if (existsSync(temporaryPath)) unlinkSync(temporaryPath);
  }
}

function writeChildResult(path: string, result: ChildResult): void {
  writePrivateJson(path, result);
}

function installChildCompletion(pi: PiLike, env: Record<string, string | undefined>): void {
  const resultFile = env[RESULT_FILE_ENV];
  const stateFile = env[STATE_FILE_ENV];
  const token = env[TOKEN_ENV];
  if (!resultFile || !token) return;
  let published = false;
  const interactive = env[INTERACTIVE_ENV] === "1";

  if (interactive) {
    let stateRevision = 0;
    let attentionLabel: string | undefined;
    const clearAttention = (): void => {
      if (!attentionLabel) return;
      pi.events.emit("herdr:blocked", { active: false, label: attentionLabel });
      attentionLabel = undefined;
    };
    const completeTask = (output: string): void => {
      if (published) throw new Error("Task has already been completed");
      const result = output.trim();
      if (!result) throw new Error("Task result must be non-empty");
      writeChildResult(resultFile, {
        schemaVersion: 1,
        token,
        status: "completed",
        output: result,
      });
      clearAttention();
      published = true;
    };
    pi.on("agent_start", () => {
      if (published || !stateFile) return;
      clearAttention();
      writePrivateJson(stateFile, {
        schemaVersion: 1,
        token,
        revision: (stateRevision += 1),
        status: "working",
      } satisfies TaskState);
    });

    pi.registerTool({
      name: "request_attention",
      label: "Request Attention",
      description:
        "Mark the interactive Task as waiting for human input and notify the parent without changing focus.",
      parameters: Type.Object({
        reason: Type.String({ description: "What input or decision is needed from the human" }),
      }),
      async execute(_toolCallId: string, params: any) {
        if (published) throw new Error("Task has already been completed");
        if (!stateFile) throw new Error("Interactive Task has no state file");
        const reason = params.reason.trim();
        if (!reason) throw new Error("Attention reason must be non-empty");
        const state: TaskState = {
          schemaVersion: 1,
          token,
          revision: (stateRevision += 1),
          status: "waiting_for_human",
          reason,
        };
        writePrivateJson(stateFile, state);
        clearAttention();
        attentionLabel = reason;
        pi.events.emit("herdr:blocked", { active: true, label: reason });
        return {
          content: [{ type: "text", text: "Human attention requested. The Task remains active." }],
          details: { status: state.status, reason },
        };
      },
    });

    pi.registerTool({
      name: "finish_task",
      label: "Finish Task",
      description:
        "Complete the interactive Task and return its final result to the parent. Use only when the human explicitly asks you to finish.",
      parameters: Type.Object({
        result: Type.String({ description: "Final result to return to the parent" }),
      }),
      async execute(_toolCallId: string, params: any) {
        completeTask(params.result);
        return {
          content: [
            { type: "text", text: "Task completed and its result was returned to the parent." },
          ],
          details: { status: "completed" },
        };
      },
    });

    pi.registerCommand("finish", {
      description: "Complete this interactive Task and return its result to the parent",
      handler: async (args: string, ctx: any) => {
        try {
          const explicitResult = args.trim();
          const result = explicitResult || assistantResult(ctx.sessionManager.getBranch()).output;
          completeTask(result);
          ctx.ui.notify("Task completed and returned to the parent", "info");
        } catch (error) {
          ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
        }
      },
    });
  } else {
    pi.on("agent_settled", (_event, ctx: any) => {
      if (published) return;
      const result = assistantResult(ctx.sessionManager.getBranch());
      writeChildResult(resultFile, {
        schemaVersion: 1,
        token,
        status: result.status,
        output: result.output,
      });
      published = true;
      ctx.shutdown();
    });
  }

  pi.on("session_shutdown", (event: any) => {
    if (published || event.reason !== "quit") return;
    writeChildResult(resultFile, {
      schemaVersion: 1,
      token,
      status: "failed",
      output: "Subagent exited before producing a final result.",
    });
    published = true;
  });
}

function resolveTools(pi: PiLike, requested: string[] | undefined): string[] {
  const available = new Set(pi.getAllTools().map((tool) => tool.name));
  const tools = requested ?? pi.getActiveTools();
  const normalized = [...new Set(tools.map((tool) => tool.trim()).filter(Boolean))].filter(
    (tool) =>
      tool !== "subagent" && tool !== "subagent_wait" && tool !== "subagent_close",
  );
  const unknown = normalized.filter((tool) => !available.has(tool));
  if (unknown.length > 0) throw new Error(`Unknown subagent tools: ${unknown.join(", ")}`);
  return normalized;
}

export function installHerdrSubagent(pi: PiLike, options: InstallOptions = {}): void {
  const env = options.env ?? process.env;
  const depth = Number.parseInt(env[DEPTH_ENV] ?? "0", 10);
  if (env[CHILD_ENV] === "1") {
    installChildCompletion(pi, env);
    return;
  }
  if (depth >= DEFAULT_MAX_DEPTH) return;

  const herdr = options.herdr ?? createHerdrClient(pi);
  const agentDirectory =
    env.PI_CODING_AGENT_DIR ?? join(env.HOME ?? process.env.HOME ?? "/tmp", ".pi", "agent");
  const artifactRoot = options.artifactRoot ?? join(agentDirectory, "subagents");
  const pollIntervalMs = options.pollIntervalMs ?? 250;
  const activeTasks = new Map<string, ActiveTask>();
  const retainedTasks = new Map<string, RetainedTask>();
  let parentUi: any;

  const renderTasks = (): void => {
    if (!parentUi) return;
    if (activeTasks.size === 0 && retainedTasks.size === 0) {
      parentUi.setWidget("herdr-subagents", undefined);
      return;
    }
    parentUi.setWidget("herdr-subagents", [
      "Subagents",
      ...[...activeTasks.values()].map(
        (task) =>
          `• ${task.name} — ${task.status === "waiting_for_human" ? "waiting for human" : "working"}`,
      ),
      ...[...retainedTasks.values()].map(
        (task) => `• ${task.name} — ${task.status}; awaiting close`,
      ),
    ]);
  };

  const settleTask = async (id: string, result: ChildResult): Promise<void> => {
    const task = activeTasks.get(id);
    if (!task || task.settling) return;
    task.settling = true;
    clearInterval(task.timer);
    activeTasks.delete(id);
    renderTasks();

    const completed = result.status === "completed" && result.output.trim().length > 0;
    const status = completed ? "completed" : "failed";
    const bounded = boundParentOutput(result.output || "No result was produced.", task.resultFile);
    const toolResult = {
      content: [
        {
          type: "text",
          text: `Subagent ${task.name} ${status}:\n\n${bounded.text}`,
        },
      ],
      details: {
        id,
        name: task.name,
        status,
        tabId: task.tabId,
        ...(bounded.truncated ? { resultFile: task.resultFile } : {}),
      },
    };
    if (task.interactive) {
      retainedTasks.set(id, {
        name: task.name,
        tabId: task.tabId,
        resultDirectory: task.resultDirectory,
        retainArtifacts: bounded.truncated,
        status,
      });
      renderTasks();
    }
    if (!task.claimed) {
      pi.sendMessage(
        {
          customType: "subagent_result",
          content: toolResult.content[0].text,
          display: true,
          details: {
            name: task.name,
            status,
            tabId: task.tabId,
            ...(bounded.truncated ? { resultFile: task.resultFile } : {}),
          },
        },
        { deliverAs: "followUp", triggerTurn: activeTasks.size === 0 },
      );
    }

    task.resolveWait?.(toolResult);
    if (completed && !task.interactive) {
      try {
        await herdr.closeTab(task.tabId);
        if (!bounded.truncated) rmSync(task.resultDirectory, { recursive: true, force: true });
      } catch {
        // The result is already durable in the parent. Leave any resource that
        // could not be safely closed for manual inspection.
      }
    }
  };

  const watchTask = (
    id: string,
    task: Omit<ActiveTask, "timer" | "settling" | "claimed" | "resolveWait">,
  ): void => {
    const timer = setInterval(() => {
      const active = activeTasks.get(id);
      if (!active) return;
      const state = readTaskState(active.stateFile, active.token);
      if (state && state.revision > active.stateRevision) {
        active.stateRevision = state.revision;
        active.status = state.status;
        renderTasks();
      }
      const result = readChildResult(active.resultFile, active.token);
      if (result) void settleTask(id, result);
    }, pollIntervalMs);
    timer.unref?.();
    activeTasks.set(id, { ...task, timer, settling: false, claimed: false });
    renderTasks();
  };

  pi.on("session_shutdown", (_event, ctx: any) => {
    for (const task of activeTasks.values()) clearInterval(task.timer);
    activeTasks.clear();
    retainedTasks.clear();
    parentUi = ctx.ui ?? parentUi;
    renderTasks();
  });

  pi.registerTool({
    name: "subagent_close",
    label: "Close subagent",
    description: "Close a completed interactive Task's retained Herdr tab.",
    parameters: Type.Object({
      id: Type.String({ description: "Task ID returned by subagent" }),
    }),
    async execute(_toolCallId: string, params: any) {
      const id = params.id.trim();
      const task = retainedTasks.get(id);
      if (!task) throw new Error(`Unknown or active interactive Task: ${id}`);
      await herdr.closeTab(task.tabId);
      retainedTasks.delete(id);
      if (!task.retainArtifacts) {
        rmSync(task.resultDirectory, { recursive: true, force: true });
      }
      renderTasks();
      return {
        content: [{ type: "text", text: `Closed interactive Task ${task.name}.` }],
        details: { id, name: task.name, status: "closed" },
      };
    },
  });

  pi.registerTool({
    name: "subagent_wait",
    label: "Wait for subagent",
    description:
      "Wait for a started subagent by Task ID and return its result. Claiming a Task prevents automatic redelivery.",
    parameters: Type.Object({
      id: Type.String({ description: "Task ID returned by subagent" }),
    }),
    async execute(_toolCallId: string, params: any, signal: AbortSignal | undefined) {
      const id = params.id.trim();
      const task = activeTasks.get(id);
      if (!task) throw new Error(`Unknown or completed subagent Task: ${id}`);
      if (task.claimed) throw new Error(`Subagent Task is already being waited for: ${id}`);
      if (signal?.aborted) throw signal.reason ?? new Error("Subagent wait aborted");
      task.claimed = true;
      task.timer.ref?.();
      return new Promise((resolve, reject) => {
        const abort = () => {
          if (task.settling) return;
          task.claimed = false;
          task.resolveWait = undefined;
          task.timer.unref?.();
          reject(signal?.reason ?? new Error("Subagent wait aborted"));
        };
        task.resolveWait = (result) => {
          signal?.removeEventListener("abort", abort);
          resolve(result);
        };
        signal?.addEventListener("abort", abort, { once: true });
      });
    },
  });

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Start a Pi subagent Task in a visible Herdr tab and return its Task ID. Autonomous Tasks return automatically; interactive Tasks remain available for human turns until finish_task or /finish completes them.",
    promptGuidelines: [
      "For autonomous Tasks, partition work before launch: give the child an independent deliverable and reserve a different parent deliverable. While it runs, work only on the reserved parent deliverable.",
      "For direct human collaboration, set interactive true and set focus true only when the human is expected to engage immediately. Call subagent_wait instead of inspecting or waiting through raw Herdr commands.",
      "Call subagent_wait for every child whose result the response depends on. After all required waits return, synthesize the combined result once.",
      "After collecting a completed interactive Task, call subagent_close when its retained tab is no longer needed.",
    ],
    parameters: Type.Object({
      name: Type.String({ description: "Short human-readable task label" }),
      task: Type.String({ description: "Complete instructions for the child" }),
      tools: Type.Optional(
        Type.Array(Type.String(), {
          description: "Exact tool allowlist; defaults to parent tools",
        }),
      ),
      model: Type.Optional(
        Type.String({
          description: "Exact provider/model-id; defaults to the parent model",
        }),
      ),
      thinking: Type.Optional(
        Type.String({
          description: "Thinking level; defaults to the parent level",
          enum: [...THINKING_LEVELS],
        }),
      ),
      interactive: Type.Optional(
        Type.Boolean({ description: "Keep the child available across human turns" }),
      ),
      focus: Type.Optional(
        Type.Boolean({ description: "Focus the child tab after launch; defaults to false" }),
      ),
    }),
    async execute(
      _toolCallId: string,
      params: any,
      _signal: AbortSignal | undefined,
      _onUpdate: unknown,
      ctx: any,
    ) {
      parentUi = ctx.ui;
      if (env.HERDR_ENV !== "1" || !env.HERDR_WORKSPACE_ID) {
        throw new Error("subagent requires Pi to be running inside Herdr");
      }
      const displayName = params.name.trim();
      const task = params.task.trim();
      if (!displayName || !task) throw new Error("subagent name and task must be non-empty");

      const parentModel = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
      const model = params.model?.trim() || parentModel;
      if (!model)
        throw new Error("No subagent model was specified and the parent has no active model");
      const parsedModel = parseModelReference(model);
      if (!ctx.modelRegistry.find(parsedModel.provider, parsedModel.model)) {
        throw new Error(`Unknown subagent model: ${model}`);
      }
      const thinking = (params.thinking ?? ctx.thinkingLevel ?? "off") as ThinkingLevel;
      const interactive = params.interactive === true;
      const tools = resolveTools(pi, params.tools);
      const childTools = interactive
        ? [...tools, "finish_task", "request_attention"]
        : tools;

      const id = randomUUID();
      const token = randomBytes(16).toString("hex");
      const resultDirectory = join(artifactRoot, id);
      const resultFile = join(resultDirectory, "result.json");
      const stateFile = join(resultDirectory, "state.json");
      mkdirSync(resultDirectory, { recursive: true, mode: 0o700 });
      const agentName = slugifyName(displayName, id);
      const surface = await herdr.createTab({
        workspaceId: env.HERDR_WORKSPACE_ID,
        cwd: ctx.cwd,
        label: displayName,
        env: {
          [CHILD_ENV]: "1",
          [DEPTH_ENV]: String(depth + 1),
          [RESULT_FILE_ENV]: resultFile,
          [STATE_FILE_ENV]: stateFile,
          [TOKEN_ENV]: token,
          ...(interactive ? { [INTERACTIVE_ENV]: "1" } : {}),
        },
      });
      await herdr.startAgent({
        name: agentName,
        paneId: surface.paneId,
        model,
        thinking,
        tools: childTools,
        systemPrompt: interactive
          ? INTERACTIVE_CHILD_SYSTEM_PROMPT
          : AUTONOMOUS_CHILD_SYSTEM_PROMPT,
      });
      await herdr.promptAgent({ name: agentName, task });
      watchTask(id, {
        name: displayName,
        interactive,
        tabId: surface.tabId,
        resultDirectory,
        resultFile,
        stateFile,
        stateRevision: 0,
        status: "working",
        token,
      });
      if (params.focus === true) await herdr.focusTab(surface.tabId);

      return {
        content: [
          {
            type: "text",
            text: `Subagent ${displayName} started in ${surface.tabId}.\nTask ID: ${id}. Use subagent_wait with this ID to collect the result in this turn.`,
          },
        ],
        details: { id, name: displayName, agentName, tabId: surface.tabId },
      };
    },
  });
}

export default function herdrSubagentExtension(pi: ExtensionAPI): void {
  installHerdrSubagent(pi as unknown as PiLike);
}
