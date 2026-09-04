import { randomBytes, randomUUID } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { isAbsolute, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const CHILD_ENV = "PI_HERDR_SUBAGENT";
const DEPTH_ENV = "PI_HERDR_SUBAGENT_DEPTH";
const RESULT_FILE_ENV = "PI_HERDR_SUBAGENT_RESULT_FILE";
const STATE_FILE_ENV = "PI_HERDR_SUBAGENT_STATE_FILE";
const TOKEN_ENV = "PI_HERDR_SUBAGENT_TOKEN";
const INTERACTIVE_ENV = "PI_HERDR_SUBAGENT_INTERACTIVE";
const PARENT_PROMPT_PREFIX = "[[pi-subagent-parent:";
const DEFAULT_MAX_DEPTH = 1;
const MAX_PARENT_OUTPUT_BYTES = 48 * 1024;
const AUTONOMOUS_CHILD_SYSTEM_PROMPT =
  "You are a delegated subagent performing one durable Task. Complete the supplied task directly and call finish_task only after the entire assignment is complete. Becoming idle or answering a human follow-up does not complete the Task. Treat your assigned cwd as the primary checkout. Do not create another worktree merely to satisfy wording that the Task should run in a worktree. You may access other repositories or use additional worktrees when the Task genuinely requires it. Call request_attention only when no useful work can continue without human input and the human is not already engaged in this tab. Do not use request_attention for ordinary back-and-forth or to ask what to do next. Do not spawn or control other agents; if a skill says to delegate your assigned work, perform it yourself.";
const INTERACTIVE_CHILD_SYSTEM_PROMPT =
  "You are working on an interactive delegated Task. Remain available across turns: becoming idle does not complete the Task. Call finish_task only when the human explicitly asks you to finish and return a result. Treat your assigned cwd as the primary checkout. Do not create another worktree merely to satisfy wording that the Task should run in a worktree. You may access other repositories or use additional worktrees when the Task genuinely requires it. Call request_attention only when no useful work can continue without human input and the human is not already engaged in this tab. Do not use request_attention for ordinary back-and-forth or to ask what to do next. Do not spawn or control other agents; perform the delegated work yourself.";

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
  label: string;
  paneId: string;
  sessionId: string;
  model: string;
  thinking: ThinkingLevel;
  tools: string[];
  systemPrompt: string;
}

interface PromptAgentRequest {
  name: string;
  token: string;
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

type ResourcePresence = "present" | "absent" | "unknown";

type ParentTaskStatus =
  | "working"
  | "waiting_for_human"
  | "interrupted"
  | "completed"
  | "failed"
  | "cancelled";

interface TaskManifest {
  schemaVersion: 1;
  id: string;
  token: string;
  parentSessionId: string;
  parentEntryId: string | null;
  name: string;
  agentName: string;
  agentSessionId: string;
  interactive: boolean;
  cwd: string;
  workspaceId: string;
  tabId: string;
  paneId: string;
  resultDirectory: string;
  resultFile: string;
  stateFile: string;
  model: string;
  thinking: ThinkingLevel;
  tools: string[];
  status: ParentTaskStatus;
  resumeStatus: "working" | "waiting_for_human";
  retainArtifacts: boolean;
  delivered: boolean;
  interruptionDelivered: boolean;
  cleaned: boolean;
  stateRevision: number;
}

interface RetainedTask {
  name: string;
  tabId: string;
  resultDirectory: string;
  retainArtifacts: boolean;
  delivered: boolean;
  status: "completed" | "failed" | "cancelled";
}

interface ActiveTask extends TaskManifest {
  manifestFile: string;
  timer: ReturnType<typeof setInterval>;
  lastLivenessCheck: number;
  checkingLiveness: boolean;
  transitioning: boolean;
  settling: boolean;
  claimed: boolean;
  resolveWait?: (result: unknown) => void;
}

export interface HerdrClient {
  createTab(request: CreateTabRequest): Promise<{ tabId: string; paneId: string }>;
  startAgent(request: StartAgentRequest): Promise<void>;
  promptAgent(request: PromptAgentRequest): Promise<void>;
  getAgentPresence(name: string): Promise<ResourcePresence>;
  getTabPresence(tabId: string): Promise<ResourcePresence>;
  stopAgent(name: string): Promise<void>;
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
  livenessIntervalMs?: number;
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

async function isCurrentPaneFocused(pi: PiLike): Promise<boolean> {
  if (!pi.exec) return false;
  try {
    const result = await pi.exec("herdr", ["pane", "current", "--current"]);
    if (result.code !== 0) return false;
    return parseHerdrResult("herdr pane current", result.stdout)?.pane?.focused === true;
  } catch {
    return false;
  }
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
        "--session-id",
        request.sessionId,
        "--name",
        request.label,
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
        await exec("herdr", [
          "agent",
          "prompt",
          request.name,
          parentPrompt(request.token, request.task),
        ]),
      );
    },
    async getAgentPresence(name) {
      const result = await exec("herdr", ["agent", "get", name]);
      if (result.code === 0) return "present";
      return hasHerdrErrorCode(result, "agent_not_found") ? "absent" : "unknown";
    },
    async getTabPresence(tabId) {
      const result = await exec("herdr", ["tab", "get", tabId]);
      if (result.code === 0) return "present";
      return hasHerdrErrorCode(result, "tab_not_found") ? "absent" : "unknown";
    },
    async stopAgent(name) {
      requireCommandSuccess(
        "herdr agent send-keys",
        await exec("herdr", ["agent", "send-keys", name, "ctrl+c"]),
      );
      await delay(100);
      const exit = await exec("herdr", ["agent", "send-keys", name, "ctrl+d"]);
      if (exit.code !== 0 && !hasHerdrErrorCode(exit, "agent_not_found")) {
        requireCommandSuccess("herdr agent send-keys", exit);
      }
      for (let attempt = 0; attempt < 30; attempt += 1) {
        const state = await exec("herdr", ["agent", "get", name]);
        if (hasHerdrErrorCode(state, "agent_not_found")) return;
        if (state.code !== 0) throw new Error("Could not verify that the subagent stopped");
        await delay(100);
      }
      throw new Error(`Subagent ${name} did not stop`);
    },
    async focusTab(tabId) {
      requireCommandSuccess("herdr tab focus", await exec("herdr", ["tab", "focus", tabId]));
    },
    async closeTab(tabId) {
      requireCommandSuccess("herdr tab close", await exec("herdr", ["tab", "close", tabId]));
    },
  };
}

function parentPrompt(token: string, message: string): string {
  return `${PARENT_PROMPT_PREFIX}${token}]]\n${message}`;
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

function readTaskManifest(path: string): TaskManifest | undefined {
  if (!existsSync(path)) return undefined;
  try {
    const manifest = JSON.parse(readFileSync(path, "utf8")) as Partial<TaskManifest>;
    if (
      manifest.schemaVersion !== 1 ||
      typeof manifest.id !== "string" ||
      typeof manifest.token !== "string" ||
      typeof manifest.parentSessionId !== "string" ||
      (manifest.parentEntryId !== null && typeof manifest.parentEntryId !== "string") ||
      typeof manifest.name !== "string" ||
      typeof manifest.agentName !== "string" ||
      typeof manifest.agentSessionId !== "string" ||
      typeof manifest.interactive !== "boolean" ||
      typeof manifest.cwd !== "string" ||
      typeof manifest.workspaceId !== "string" ||
      typeof manifest.tabId !== "string" ||
      typeof manifest.paneId !== "string" ||
      typeof manifest.resultDirectory !== "string" ||
      typeof manifest.resultFile !== "string" ||
      typeof manifest.stateFile !== "string" ||
      typeof manifest.model !== "string" ||
      !THINKING_LEVELS.includes(manifest.thinking as ThinkingLevel) ||
      !Array.isArray(manifest.tools) ||
      typeof manifest.retainArtifacts !== "boolean" ||
      typeof manifest.delivered !== "boolean" ||
      (manifest.interruptionDelivered !== undefined &&
        typeof manifest.interruptionDelivered !== "boolean") ||
      typeof manifest.cleaned !== "boolean" ||
      !["working", "waiting_for_human", "interrupted", "completed", "failed", "cancelled"].includes(
        manifest.status ?? "",
      ) ||
      (manifest.resumeStatus !== "working" && manifest.resumeStatus !== "waiting_for_human") ||
      !Number.isInteger(manifest.stateRevision)
    ) {
      return undefined;
    }
    return {
      ...manifest,
      interruptionDelivered: manifest.interruptionDelivered ?? false,
    } as TaskManifest;
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
  let published = readChildResult(resultFile, token) !== undefined;
  const interactive = env[INTERACTIVE_ENV] === "1";

  {
    const initialState = stateFile ? readTaskState(stateFile, token) : undefined;
    let stateRevision = initialState?.revision ?? 0;
    let humanInputRevision = 0;
    let attentionPending = initialState?.status === "waiting_for_human";
    let attentionReason = attentionPending ? initialState?.reason : undefined;
    let attentionLabel = attentionReason;
    const clearAttention = (): void => {
      attentionPending = false;
      attentionReason = undefined;
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
    pi.on("input", (event: any) => {
      const marker = `${PARENT_PROMPT_PREFIX}${token}]]\n`;
      if (typeof event.text === "string" && event.text.startsWith(marker)) {
        return { action: "transform", text: event.text.slice(marker.length), images: event.images };
      }
      const directHumanInput = event.source === "interactive" || event.source === "rpc";
      if (directHumanInput) humanInputRevision += 1;
      if (!published && attentionPending && stateFile && directHumanInput) {
        clearAttention();
        writePrivateJson(stateFile, {
          schemaVersion: 1,
          token,
          revision: (stateRevision += 1),
          status: "working",
        } satisfies TaskState);
      }
      return { action: "continue" };
    });

    pi.registerTool({
      name: "request_attention",
      label: "Request Attention",
      description:
        "Escalate when the Task cannot continue useful work without human input and the human is not already engaged. Do not use for ordinary conversation.",
      parameters: Type.Object({
        reason: Type.String({ description: "What input or decision is needed from the human" }),
      }),
      async execute(_toolCallId: string, params: any) {
        if (published) throw new Error("Task has already been completed");
        if (!stateFile) throw new Error("Task has no state file");
        const reason = params.reason.trim();
        if (!reason) throw new Error("Attention reason must be non-empty");
        if (attentionPending) {
          return {
            content: [{ type: "text", text: "Human attention is already pending." }],
            details: {
              status: "waiting_for_human",
              reason: attentionReason,
              notified: false,
            },
          };
        }
        const observedRevision = stateRevision;
        const observedHumanInputRevision = humanInputRevision;
        const focused = await isCurrentPaneFocused(pi);
        if (
          published ||
          stateRevision !== observedRevision ||
          humanInputRevision !== observedHumanInputRevision ||
          attentionPending
        ) {
          return {
            content: [{ type: "text", text: "The Task state changed before attention was requested." }],
            details: { status: "working", reason, notified: false },
          };
        }
        if (focused) {
          return {
            content: [{ type: "text", text: "The human is already engaged in this conversation." }],
            details: { status: "working", reason, notified: false },
          };
        }
        const state: TaskState = {
          schemaVersion: 1,
          token,
          revision: (stateRevision += 1),
          status: "waiting_for_human",
          reason,
        };
        writePrivateJson(stateFile, state);
        attentionPending = true;
        attentionReason = reason;
        attentionLabel = reason;
        pi.events.emit("herdr:blocked", { active: true, label: reason });
        return {
          content: [{ type: "text", text: "Human attention requested. The Task remains active." }],
          details: { status: state.status, reason, notified: true },
        };
      },
    });

    pi.registerTool({
      name: "finish_task",
      label: "Finish Task",
      description:
        "Explicitly complete the whole Task and return its final result to the parent. Interactive Tasks require the human to ask for completion.",
      parameters: Type.Object({
        result: Type.String({ description: "Final result to return to the parent" }),
      }),
      async execute(
        _toolCallId: string,
        params: any,
        _signal: AbortSignal | undefined,
        _onUpdate: unknown,
        ctx: any,
      ) {
        completeTask(params.result);
        if (!interactive) ctx.shutdown();
        return {
          content: [
            { type: "text", text: "Task completed and its result was returned to the parent." },
          ],
          details: { status: "completed" },
          ...(interactive ? {} : { terminate: true }),
        };
      },
    });

    pi.registerCommand("finish", {
      description: "Explicitly complete this Task and return its result to the parent",
      handler: async (args: string, ctx: any) => {
        try {
          const explicitResult = args.trim();
          const result = explicitResult || assistantResult(ctx.sessionManager.getBranch()).output;
          completeTask(result);
          if (!interactive) ctx.shutdown();
          ctx.ui.notify("Task completed and returned to the parent", "info");
        } catch (error) {
          ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
        }
      },
    });

    pi.on("session_shutdown", () => {
      clearAttention();
      // No Result is written. An unfinished saved Agent conversation remains resumable.
    });
  }
}

function resolveTools(pi: PiLike, requested: string[] | undefined): string[] {
  const available = new Set(pi.getAllTools().map((tool) => tool.name));
  const tools = requested ?? pi.getActiveTools();
  const normalized = [...new Set(tools.map((tool) => tool.trim()).filter(Boolean))].filter(
    (tool) =>
      tool !== "subagent" &&
      tool !== "subagent_send" &&
      tool !== "subagent_cancel" &&
      tool !== "subagent_wait" &&
      tool !== "subagent_close",
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
  const livenessIntervalMs = options.livenessIntervalMs ?? 2_000;
  const activeTasks = new Map<string, ActiveTask>();
  const retainedTasks = new Map<string, RetainedTask>();
  const closingTasks = new Set<string>();
  let parentUi: any;
  let parentSessionManager: any;

  const persistTaskManifest = (task: TaskManifest): void => {
    writePrivateJson(join(task.resultDirectory, "task.json"), task);
  };

  const persistActiveTask = (task: ActiveTask): void => {
    const {
      timer: _timer,
      settling: _settling,
      claimed: _claimed,
      resolveWait: _resolveWait,
      lastLivenessCheck: _lastLivenessCheck,
      checkingLiveness: _checkingLiveness,
      transitioning: _transitioning,
      manifestFile,
      ...manifest
    } = task;
    writePrivateJson(manifestFile, manifest satisfies TaskManifest);
  };

  const currentBranchOwns = (task: TaskManifest): boolean => {
    if (!task.parentEntryId) return true;
    return Boolean(
      parentSessionManager
        ?.getBranch?.()
        ?.some((entry: any) => entry?.id === task.parentEntryId),
    );
  };

  const recordedDeliveryExists = (task: TaskManifest): boolean =>
    Boolean(
      parentSessionManager?.getEntries?.().some(
        (entry: any) =>
          entry?.type === "custom_message" &&
          entry?.customType === "subagent_result" &&
          entry?.details?.id === task.id,
      ),
    );

  const finalizeCleanedTask = (task: TaskManifest): void => {
    if (!task.cleaned || !task.delivered) return;
    if (task.retainArtifacts) {
      rmSync(join(task.resultDirectory, "task.json"), { force: true });
      rmSync(join(task.resultDirectory, "state.json"), { force: true });
    } else {
      rmSync(task.resultDirectory, { recursive: true, force: true });
    }
  };

  const startTransition = (task: ActiveTask): (() => void) => {
    if (task.transitioning) throw new Error(`Subagent Task is already changing state: ${task.id}`);
    task.transitioning = true;
    return () => {
      if (activeTasks.get(task.id) === task) task.transitioning = false;
    };
  };

  const startTaskAgent = (task: TaskManifest): Promise<void> =>
    herdr.startAgent({
      name: task.agentName,
      label: task.name,
      paneId: task.paneId,
      sessionId: task.agentSessionId,
      model: task.model,
      thinking: task.thinking,
      tools: task.tools,
      systemPrompt: task.interactive
        ? INTERACTIVE_CHILD_SYSTEM_PROMPT
        : AUTONOMOUS_CHILD_SYSTEM_PROMPT,
    });

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
          `• ${task.name} — ${
            task.status === "waiting_for_human"
              ? "waiting for human"
              : task.status === "interrupted"
                ? "interrupted"
                : "working"
          }`,
      ),
      ...[...retainedTasks.values()].map(
        (task) =>
          `• ${task.name} — ${task.status}; ${task.delivered ? "awaiting close" : "awaiting delivery"}`,
      ),
    ]);
  };

  const interruptionNotice = (task: ActiveTask) => ({
    content: [
      {
        type: "text",
        text: `Subagent ${task.name} was interrupted before completing. Its Agent conversation can be resumed with subagent_send.`,
      },
    ],
    details: { id: task.id, name: task.name, status: "interrupted", tabId: task.tabId },
  });

  const deliverInterruption = (task: ActiveTask): void => {
    if (task.interruptionDelivered || !currentBranchOwns(task)) return;
    const result = interruptionNotice(task);
    pi.sendMessage(
      {
        customType: "subagent_interrupted",
        content: result.content[0].text,
        display: true,
        details: result.details,
      },
      { deliverAs: "followUp", triggerTurn: true },
    );
    task.interruptionDelivered = true;
    persistActiveTask(task);
  };

  const markInterrupted = (task: ActiveTask): void => {
    if (
      activeTasks.get(task.id) !== task ||
      task.status === "interrupted" ||
      task.transitioning ||
      task.settling
    ) {
      return;
    }
    task.resumeStatus = task.status === "waiting_for_human" ? "waiting_for_human" : "working";
    task.status = "interrupted";
    task.interruptionDelivered = false;
    persistActiveTask(task);
    renderTasks();
    if (task.claimed) {
      task.claimed = false;
      task.timer.unref?.();
      const resolve = task.resolveWait;
      task.resolveWait = undefined;
      task.interruptionDelivered = true;
      persistActiveTask(task);
      resolve?.(interruptionNotice(task));
    } else {
      deliverInterruption(task);
    }
  };

  const settleTask = async (id: string, result: ChildResult): Promise<void> => {
    const task = activeTasks.get(id);
    if (!task || task.settling) return;
    task.settling = true;
    clearInterval(task.timer);
    activeTasks.delete(id);

    const completed = result.status === "completed" && result.output.trim().length > 0;
    const status = completed ? "completed" : "failed";
    task.status = status;
    const bounded = boundParentOutput(result.output || "No result was produced.", task.resultFile);
    task.retainArtifacts = bounded.truncated;
    persistActiveTask(task);
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

    if (task.claimed) {
      task.delivered = true;
      persistActiveTask(task);
      task.resolveWait?.(toolResult);
    } else if (currentBranchOwns(task)) {
      pi.sendMessage(
        {
          customType: "subagent_result",
          content: toolResult.content[0].text,
          display: true,
          details: {
            id,
            name: task.name,
            status,
            tabId: task.tabId,
            ...(bounded.truncated ? { resultFile: task.resultFile } : {}),
          },
        },
        { deliverAs: "followUp", triggerTurn: activeTasks.size === 0 },
      );
      task.delivered = true;
      persistActiveTask(task);
    } else {
      persistActiveTask(task);
    }

    if (completed && !task.interactive) {
      try {
        await herdr.closeTab(task.tabId);
        task.cleaned = true;
        persistActiveTask(task);
      } catch {
        // Keep ownership so explicit close or startup reconciliation can retry.
      }
    }

    if (task.cleaned && task.delivered) {
      finalizeCleanedTask(task);
    } else {
      retainedTasks.set(id, {
        name: task.name,
        tabId: task.tabId,
        resultDirectory: task.resultDirectory,
        retainArtifacts: task.retainArtifacts,
        delivered: task.delivered,
        status,
      });
    }
    renderTasks();
  };

  const watchTask = (
    id: string,
    task: Omit<
      ActiveTask,
      | "timer"
      | "settling"
      | "claimed"
      | "resolveWait"
      | "lastLivenessCheck"
      | "checkingLiveness"
      | "transitioning"
    >,
  ): void => {
    const timer = setInterval(() => {
      const active = activeTasks.get(id);
      if (!active || active.transitioning) return;
      const state = readTaskState(active.stateFile, active.token);
      if (state && state.revision > active.stateRevision) {
        active.stateRevision = state.revision;
        active.status = state.status;
        active.resumeStatus = state.status;
        persistActiveTask(active);
        renderTasks();
      }
      const result = readChildResult(active.resultFile, active.token);
      if (result) {
        void settleTask(id, result);
        return;
      }
      const now = Date.now();
      if (
        active.status !== "interrupted" &&
        !active.checkingLiveness &&
        now - active.lastLivenessCheck >= livenessIntervalMs
      ) {
        active.lastLivenessCheck = now;
        active.checkingLiveness = true;
        void herdr
          .getAgentPresence(active.agentName)
          .then((presence) => {
            if (
              presence === "absent" &&
              !readChildResult(active.resultFile, active.token)
            ) {
              markInterrupted(active);
            }
          })
          .catch(() => {
            // Indeterminate Herdr failures must not change Task state.
          })
          .finally(() => {
            active.checkingLiveness = false;
          });
      }
    }, pollIntervalMs);
    timer.unref?.();
    activeTasks.set(id, {
      ...task,
      timer,
      settling: false,
      claimed: false,
      lastLivenessCheck: 0,
      checkingLiveness: false,
      transitioning: false,
    });
    renderTasks();
  };

  const reconcileTerminalTask = async (manifest: TaskManifest): Promise<void> => {
    if (recordedDeliveryExists(manifest)) manifest.delivered = true;
    const result = readChildResult(manifest.resultFile, manifest.token);
    if (!manifest.delivered && currentBranchOwns(manifest) && result) {
      const status = result.status === "completed" && result.output.trim() ? "completed" : "failed";
      const bounded = boundParentOutput(result.output || "No result was produced.", manifest.resultFile);
      pi.sendMessage(
        {
          customType: "subagent_result",
          content: `Subagent ${manifest.name} ${status}:\n\n${bounded.text}`,
          display: true,
          details: {
            id: manifest.id,
            name: manifest.name,
            status,
            tabId: manifest.tabId,
            ...(bounded.truncated ? { resultFile: manifest.resultFile } : {}),
          },
        },
        { deliverAs: "followUp", triggerTurn: activeTasks.size === 0 },
      );
      manifest.delivered = true;
    }

    if (manifest.status === "completed" && !manifest.interactive && !manifest.cleaned) {
      const tabPresence = await herdr.getTabPresence(manifest.tabId);
      if (tabPresence === "absent") manifest.cleaned = true;
      if (tabPresence === "present") {
        try {
          await herdr.closeTab(manifest.tabId);
          manifest.cleaned = true;
        } catch {
          // Keep ownership for explicit cleanup.
        }
      }
    }

    persistTaskManifest(manifest);
    if (manifest.cleaned && manifest.delivered) {
      retainedTasks.delete(manifest.id);
      finalizeCleanedTask(manifest);
      return;
    }
    retainedTasks.set(manifest.id, {
      name: manifest.name,
      tabId: manifest.tabId,
      resultDirectory: manifest.resultDirectory,
      retainArtifacts: manifest.retainArtifacts,
      delivered: manifest.delivered,
      status:
        manifest.status === "completed"
          ? "completed"
          : manifest.status === "cancelled"
            ? "cancelled"
            : "failed",
    });
  };

  const restoreOwnedTasks = async (ctx: any): Promise<void> => {
    parentUi = ctx.ui ?? parentUi;
    parentSessionManager = ctx.sessionManager ?? parentSessionManager;
    const parentSessionId = parentSessionManager?.getSessionId?.();
    if (!parentSessionId || !existsSync(artifactRoot)) {
      renderTasks();
      return;
    }
    for (const entry of readdirSync(artifactRoot, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const manifestFile = join(artifactRoot, entry.name, "task.json");
      const manifest = readTaskManifest(manifestFile);
      if (!manifest || manifest.parentSessionId !== parentSessionId) continue;
      const savedResult = readChildResult(manifest.resultFile, manifest.token);
      if (savedResult) {
        if (activeTasks.has(manifest.id)) {
          await settleTask(manifest.id, savedResult);
          continue;
        }
        manifest.status =
          savedResult.status === "completed" && savedResult.output.trim() ? "completed" : "failed";
        manifest.retainArtifacts = boundParentOutput(
          savedResult.output || "No result was produced.",
          manifest.resultFile,
        ).truncated;
        persistTaskManifest(manifest);
        await reconcileTerminalTask(manifest);
        continue;
      }
      if (
        manifest.status === "working" ||
        manifest.status === "waiting_for_human" ||
        manifest.status === "interrupted"
      ) {
        if (!activeTasks.has(manifest.id)) watchTask(manifest.id, { ...manifest, manifestFile });
        const active = activeTasks.get(manifest.id);
        if (active?.status === "interrupted" && !active.claimed) deliverInterruption(active);
      } else {
        await reconcileTerminalTask(manifest);
      }
    }
    renderTasks();
  };

  pi.on("session_start", (_event, ctx: any) => restoreOwnedTasks(ctx));
  pi.on("session_tree", (_event, ctx: any) => restoreOwnedTasks(ctx));

  pi.on("session_shutdown", (_event, ctx: any) => {
    for (const task of activeTasks.values()) clearInterval(task.timer);
    activeTasks.clear();
    retainedTasks.clear();
    closingTasks.clear();
    parentSessionManager = undefined;
    parentUi = ctx.ui ?? parentUi;
    renderTasks();
  });

  pi.registerTool({
    name: "subagent_cancel",
    label: "Cancel subagent",
    description: "Cancel an active subagent Task while retaining its tab and artifacts for review.",
    parameters: Type.Object({
      id: Type.String({ description: "Task ID returned by subagent" }),
    }),
    async execute(_toolCallId: string, params: any) {
      const id = params.id.trim();
      const task = activeTasks.get(id);
      if (!task) throw new Error(`Unknown or terminal subagent Task: ${id}`);
      if (!currentBranchOwns(task)) {
        throw new Error(`Subagent Task belongs to another conversation branch: ${id}`);
      }
      const finishTransition = startTransition(task);
      try {
        const agentPresence = await herdr.getAgentPresence(task.agentName);
        if (agentPresence === "unknown") {
          throw new Error(`Could not verify whether subagent ${task.agentName} is still running`);
        }
        if (agentPresence === "present") await herdr.stopAgent(task.agentName);
        clearInterval(task.timer);
        task.status = "cancelled";
        task.delivered = true;
        persistActiveTask(task);
        activeTasks.delete(id);
        retainedTasks.set(id, {
          name: task.name,
          tabId: task.tabId,
          resultDirectory: task.resultDirectory,
          retainArtifacts: false,
          delivered: true,
          status: "cancelled",
        });
        const result = {
          content: [{ type: "text", text: `Cancelled subagent Task ${task.name}.` }],
          details: { id, name: task.name, status: "cancelled" },
        };
        const resolve = task.resolveWait;
        task.resolveWait = undefined;
        task.claimed = false;
        resolve?.(result);
        renderTasks();
        return result;
      } finally {
        finishTransition();
      }
    },
  });

  pi.registerTool({
    name: "subagent_close",
    label: "Close subagent",
    description: "Close a terminal subagent Task's retained Herdr tab and clean its artifacts.",
    parameters: Type.Object({
      id: Type.String({ description: "Task ID returned by subagent" }),
    }),
    async execute(_toolCallId: string, params: any) {
      const id = params.id.trim();
      const task = retainedTasks.get(id);
      if (!task) throw new Error(`Unknown or active subagent Task: ${id}`);
      if (!task.delivered) {
        throw new Error(`Subagent Task belongs to another conversation branch: ${id}`);
      }
      if (closingTasks.has(id)) throw new Error(`Subagent Task is already closing: ${id}`);
      closingTasks.add(id);
      try {
        const tabPresence = await herdr.getTabPresence(task.tabId);
        if (tabPresence === "unknown") {
          throw new Error(`Could not verify whether subagent tab ${task.tabId} is still open`);
        }
        if (tabPresence === "present") await herdr.closeTab(task.tabId);
        retainedTasks.delete(id);
        if (!task.retainArtifacts) {
          rmSync(task.resultDirectory, { recursive: true, force: true });
        } else {
          rmSync(join(task.resultDirectory, "task.json"), { force: true });
          rmSync(join(task.resultDirectory, "state.json"), { force: true });
        }
        renderTasks();
        return {
          content: [{ type: "text", text: `Closed subagent Task ${task.name}.` }],
          details: { id, name: task.name, status: "closed" },
        };
      } finally {
        closingTasks.delete(id);
      }
    },
  });

  pi.registerTool({
    name: "subagent_send",
    label: "Send to subagent",
    description: "Send follow-up direction to an active subagent Task without completing it.",
    parameters: Type.Object({
      id: Type.String({ description: "Task ID returned by subagent" }),
      message: Type.String({ description: "Follow-up direction for the child Agent" }),
    }),
    async execute(_toolCallId: string, params: any) {
      const id = params.id.trim();
      const message = params.message.trim();
      if (!message) throw new Error("Subagent message must be non-empty");
      const task = activeTasks.get(id);
      if (!task) throw new Error(`Unknown or completed subagent Task: ${id}`);
      if (!currentBranchOwns(task)) {
        throw new Error(`Subagent Task belongs to another conversation branch: ${id}`);
      }
      const finishTransition = startTransition(task);
      try {
        if (task.status === "interrupted") {
          const agentPresence = await herdr.getAgentPresence(task.agentName);
          if (agentPresence === "unknown") {
            throw new Error(`Could not verify whether subagent ${task.agentName} is still running`);
          }
          if (agentPresence === "absent") {
            const tabPresence = await herdr.getTabPresence(task.tabId);
            if (tabPresence === "unknown") {
              throw new Error(`Could not verify whether subagent tab ${task.tabId} is still open`);
            }
            if (tabPresence === "absent") {
              const surface = await herdr.createTab({
                workspaceId: env.HERDR_WORKSPACE_ID ?? task.workspaceId,
                cwd: task.cwd,
                label: task.name,
                env: {
                  [CHILD_ENV]: "1",
                  [DEPTH_ENV]: String(depth + 1),
                  [RESULT_FILE_ENV]: task.resultFile,
                  [STATE_FILE_ENV]: task.stateFile,
                  [TOKEN_ENV]: task.token,
                  ...(task.interactive ? { [INTERACTIVE_ENV]: "1" } : {}),
                },
              });
              task.workspaceId = env.HERDR_WORKSPACE_ID ?? task.workspaceId;
              task.tabId = surface.tabId;
              task.paneId = surface.paneId;
              persistActiveTask(task);
            }
            try {
              await startTaskAgent(task);
            } catch (error) {
              const presenceAfterStart = await herdr.getAgentPresence(task.agentName);
              if (presenceAfterStart === "present") task.status = task.resumeStatus;
              persistActiveTask(task);
              throw error;
            }
          }
          task.status = task.resumeStatus;
          persistActiveTask(task);
        }
        await herdr.promptAgent({ name: task.agentName, token: task.token, task: message });
        if (task.status !== "waiting_for_human") task.status = "working";
        persistActiveTask(task);
        renderTasks();
        return {
          content: [{ type: "text", text: `Sent follow-up direction to ${task.name}.` }],
          details: { id, name: task.name, status: task.status },
        };
      } finally {
        finishTransition();
      }
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
      if (!currentBranchOwns(task)) {
        throw new Error(`Subagent Task belongs to another conversation branch: ${id}`);
      }
      if (task.claimed) throw new Error(`Subagent Task is already being waited for: ${id}`);
      if (task.status === "interrupted") {
        task.interruptionDelivered = true;
        persistActiveTask(task);
        return interruptionNotice(task);
      }
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
      "Use subagent_send to steer a running child or resume an interrupted saved Agent. Do not treat idle or a normal child response as Task completion.",
      "Use subagent_cancel to terminally cancel active work. After collecting a completed interactive Task or reviewing a failed or cancelled Task, call subagent_close when its retained tab is no longer needed.",
      "When a Task has a designated existing checkout or worktree outside the parent cwd, pass its absolute path as subagent cwd so Pi loads the correct primary project context. Do not rely on a later child cd to establish that primary context.",
    ],
    parameters: Type.Object({
      name: Type.String({ description: "Short human-readable task label" }),
      task: Type.String({ description: "Complete instructions for the child" }),
      cwd: Type.Optional(
        Type.String({
          description:
            "Absolute path to an existing checkout for the child; defaults to the parent cwd",
        }),
      ),
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
      parentSessionManager = ctx.sessionManager;
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
      const requestedCwd = params.cwd?.trim();
      if (requestedCwd && !isAbsolute(requestedCwd)) {
        throw new Error(`Subagent cwd must be an absolute path: ${requestedCwd}`);
      }
      let cwd = ctx.cwd;
      if (requestedCwd) {
        try {
          cwd = realpathSync(requestedCwd);
          if (!statSync(cwd).isDirectory()) throw new Error("not a directory");
        } catch (error) {
          throw new Error(`Subagent cwd must be an existing directory: ${requestedCwd}`, {
            cause: error,
          });
        }
      }
      const tools = resolveTools(pi, params.tools);
      const childTools = [...new Set([...tools, "finish_task", "request_attention"])];

      const id = randomUUID();
      const token = randomBytes(16).toString("hex");
      const parentSessionId = ctx.sessionManager.getSessionId();
      const parentEntryId = ctx.sessionManager.getLeafId?.() ?? null;
      const resultDirectory = join(artifactRoot, id);
      const resultFile = join(resultDirectory, "result.json");
      const stateFile = join(resultDirectory, "state.json");
      const manifestFile = join(resultDirectory, "task.json");
      mkdirSync(resultDirectory, { recursive: true, mode: 0o700 });
      const agentName = slugifyName(displayName, id);
      let surface: { tabId: string; paneId: string };
      try {
        surface = await herdr.createTab({
          workspaceId: env.HERDR_WORKSPACE_ID,
          cwd,
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
      } catch (error) {
        rmSync(resultDirectory, { recursive: true, force: true });
        throw error;
      }
      const manifest: TaskManifest = {
        schemaVersion: 1,
        id,
        token,
        parentSessionId,
        parentEntryId,
        name: displayName,
        agentName,
        agentSessionId: id,
        interactive,
        cwd,
        workspaceId: env.HERDR_WORKSPACE_ID,
        tabId: surface.tabId,
        paneId: surface.paneId,
        resultDirectory,
        resultFile,
        stateFile,
        model,
        thinking,
        tools: childTools,
        status: "working",
        resumeStatus: "working",
        retainArtifacts: false,
        delivered: false,
        interruptionDelivered: false,
        cleaned: false,
        stateRevision: 0,
      };
      try {
        writePrivateJson(manifestFile, manifest);
      } catch (error) {
        try {
          await herdr.closeTab(surface.tabId);
          rmSync(resultDirectory, { recursive: true, force: true });
        } catch {
          throw new Error(
            `Could not persist subagent Task ${id}; Herdr tab ${surface.tabId} requires manual cleanup`,
            { cause: error },
          );
        }
        throw error;
      }
      try {
        await startTaskAgent(manifest);
      } catch (error) {
        let presence: ResourcePresence = "unknown";
        try {
          presence = await herdr.getAgentPresence(agentName);
        } catch {
          // The manifest still makes this launch recoverable after an indeterminate probe.
        }
        manifest.status = presence === "absent" ? "interrupted" : "working";
        writePrivateJson(manifestFile, manifest);
        watchTask(id, { ...manifest, manifestFile });
        throw new Error(`Subagent ${displayName} could not finish launching. Task ID: ${id}`, {
          cause: error,
        });
      }
      try {
        await herdr.promptAgent({ name: agentName, token, task });
      } catch (error) {
        writePrivateJson(manifestFile, manifest);
        watchTask(id, { ...manifest, manifestFile });
        throw new Error(`Subagent ${displayName} started but was not prompted. Task ID: ${id}`, {
          cause: error,
        });
      }
      watchTask(id, { ...manifest, manifestFile });
      if (params.focus === true) {
        try {
          await herdr.focusTab(surface.tabId);
        } catch {
          parentUi?.notify?.(
            `Subagent ${displayName} started in ${surface.tabId}, but its tab could not be focused`,
            "warning",
          );
        }
      }

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
