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
const TOKEN_ENV = "PI_HERDR_SUBAGENT_TOKEN";
const DEFAULT_MAX_DEPTH = 1;
const MAX_PARENT_OUTPUT_BYTES = 48 * 1024;
const CHILD_SYSTEM_PROMPT =
  "You are a delegated subagent. Complete the supplied task directly. Do not spawn or control other agents. If a skill says to delegate the work assigned to you, perform that work yourself instead.";

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

interface ActiveJob {
  name: string;
  tabId: string;
  resultDirectory: string;
  resultFile: string;
  token: string;
  timer: ReturnType<typeof setInterval>;
  settling: boolean;
}

export interface HerdrClient {
  createTab(request: CreateTabRequest): Promise<{ tabId: string; paneId: string }>;
  startAgent(request: StartAgentRequest): Promise<void>;
  promptAgent(request: PromptAgentRequest): Promise<void>;
  closeTab(tabId: string): Promise<void>;
}

interface ToolDefinition {
  name: string;
  [key: string]: unknown;
}

interface PiLike {
  registerTool(tool: ToolDefinition): void;
  on(event: string, handler: (event: unknown, ctx: any) => unknown): void;
  getActiveTools(): string[];
  getAllTools(): Array<{ name: string }>;
  sendMessage(message: unknown, options?: unknown): void;
  exec?(command: string, args: string[], options?: unknown): Promise<{
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
    throw new Error(`${command} failed: ${result.stderr.trim() || result.stdout.trim() || `exit ${result.code}`}`);
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

function parseModelReference(reference: string): { provider: string; model: string } {
  const separator = reference.indexOf("/");
  if (separator <= 0 || separator === reference.length - 1) {
    throw new Error(`Model must be an exact provider/model-id reference: ${reference}`);
  }
  return { provider: reference.slice(0, separator), model: reference.slice(separator + 1) };
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

function boundParentOutput(output: string, resultFile: string): { text: string; truncated: boolean } {
  const bytes = Buffer.from(output, "utf8");
  if (bytes.length <= MAX_PARENT_OUTPUT_BYTES) return { text: output, truncated: false };
  const prefix = bytes.subarray(0, MAX_PARENT_OUTPUT_BYTES).toString("utf8").replace(/\uFFFD$/, "");
  return {
    text: `${prefix}\n\n[Output truncated. Full result retained at ${resultFile}]`,
    truncated: true,
  };
}

function assistantResult(entries: any[]): { status: "completed" | "failed"; output: string } {
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
  return { status: "failed", output: "No final assistant response was produced." };
}

function writeChildResult(path: string, result: ChildResult): void {
  const temporaryPath = `${path}.${process.pid}.tmp`;
  try {
    writeFileSync(temporaryPath, `${JSON.stringify(result, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
    renameSync(temporaryPath, path);
  } finally {
    if (existsSync(temporaryPath)) unlinkSync(temporaryPath);
  }
}

function installChildCompletion(pi: PiLike, env: Record<string, string | undefined>): void {
  const resultFile = env[RESULT_FILE_ENV];
  const token = env[TOKEN_ENV];
  if (!resultFile || !token) return;
  let published = false;

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
    (tool) => tool !== "subagent",
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
  const jobs = new Map<string, ActiveJob>();
  let parentUi: any;

  const renderJobs = (): void => {
    if (!parentUi) return;
    if (jobs.size === 0) {
      parentUi.setWidget("herdr-subagents", undefined);
      return;
    }
    parentUi.setWidget("herdr-subagents", [
      "Subagents",
      ...[...jobs.values()].map((job) => `• ${job.name} — working`),
    ]);
  };

  const settleJob = async (id: string, result: ChildResult): Promise<void> => {
    const job = jobs.get(id);
    if (!job || job.settling) return;
    job.settling = true;
    clearInterval(job.timer);
    jobs.delete(id);
    renderJobs();

    const completed = result.status === "completed" && result.output.trim().length > 0;
    const status = completed ? "completed" : "failed";
    const bounded = boundParentOutput(result.output || "No result was produced.", job.resultFile);
    pi.sendMessage(
      {
        customType: "subagent_result",
        content: `Subagent ${job.name} ${status}:\n\n${bounded.text}`,
        display: true,
        details: {
          name: job.name,
          status,
          tabId: job.tabId,
          ...(bounded.truncated ? { resultFile: job.resultFile } : {}),
        },
      },
      { deliverAs: "followUp", triggerTurn: jobs.size === 0 },
    );

    if (!completed) return;
    try {
      await herdr.closeTab(job.tabId);
      if (!bounded.truncated) rmSync(job.resultDirectory, { recursive: true, force: true });
    } catch {
      // The result is already durable in the parent. Leave any resource that
      // could not be safely closed for manual inspection.
    }
  };

  const watchJob = (id: string, job: Omit<ActiveJob, "timer" | "settling">): void => {
    const timer = setInterval(() => {
      const result = readChildResult(job.resultFile, job.token);
      if (result) void settleJob(id, result);
    }, pollIntervalMs);
    timer.unref?.();
    jobs.set(id, { ...job, timer, settling: false });
    renderJobs();
  };

  pi.on("session_shutdown", (_event, ctx: any) => {
    for (const job of jobs.values()) clearInterval(job.timer);
    jobs.clear();
    parentUi = ctx.ui ?? parentUi;
    renderJobs();
  });

  pi.registerTool({
    name: "subagent",
    label: "Subagent",
    description:
      "Start one autonomous Pi subagent in a visible Herdr tab. Returns immediately; the final result is delivered later. Multiple calls run independently.",
    parameters: Type.Object({
      name: Type.String({ description: "Short human-readable task label" }),
      task: Type.String({ description: "Complete instructions for the child" }),
      tools: Type.Optional(Type.Array(Type.String(), { description: "Exact tool allowlist; defaults to parent tools" })),
      model: Type.Optional(Type.String({ description: "Exact provider/model-id; defaults to the parent model" })),
      thinking: Type.Optional(
        Type.String({
          description: "Thinking level; defaults to the parent level",
          enum: [...THINKING_LEVELS],
        }),
      ),
    }),
    async execute(_toolCallId: string, params: any, _signal: AbortSignal | undefined, _onUpdate: unknown, ctx: any) {
      parentUi = ctx.ui;
      if (env.HERDR_ENV !== "1" || !env.HERDR_WORKSPACE_ID) {
        throw new Error("subagent requires Pi to be running inside Herdr");
      }
      const displayName = params.name.trim();
      const task = params.task.trim();
      if (!displayName || !task) throw new Error("subagent name and task must be non-empty");

      const parentModel = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
      const model = params.model?.trim() || parentModel;
      if (!model) throw new Error("No subagent model was specified and the parent has no active model");
      const parsedModel = parseModelReference(model);
      if (!ctx.modelRegistry.find(parsedModel.provider, parsedModel.model)) {
        throw new Error(`Unknown subagent model: ${model}`);
      }
      const thinking = (params.thinking ?? ctx.thinkingLevel ?? "off") as ThinkingLevel;
      const tools = resolveTools(pi, params.tools);

      const id = randomUUID();
      const token = randomBytes(16).toString("hex");
      const resultDirectory = join(artifactRoot, id);
      const resultFile = join(resultDirectory, "result.json");
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
          [TOKEN_ENV]: token,
        },
      });
      await herdr.startAgent({
        name: agentName,
        paneId: surface.paneId,
        model,
        thinking,
        tools,
        systemPrompt: CHILD_SYSTEM_PROMPT,
      });
      await herdr.promptAgent({ name: agentName, task });
      watchJob(id, {
        name: displayName,
        tabId: surface.tabId,
        resultDirectory,
        resultFile,
        token,
      });

      return {
        content: [{ type: "text", text: `Subagent ${displayName} started in ${surface.tabId}.` }],
        details: { id, name: displayName, agentName, tabId: surface.tabId },
      };
    },
  });
}

export default function herdrSubagentExtension(pi: ExtensionAPI): void {
  installHerdrSubagent(pi as unknown as PiLike);
}
