// Temporary host-notification bridge until Pi exposes UI wait events upstream:
// https://github.com/earendil-works/pi/issues/5329
// https://github.com/earendil-works/pi/issues/7147
import { randomUUID } from "node:crypto";
import { createConnection as nodeCreateConnection } from "node:net";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const HUMAN_ATTENTION_REQUESTED = "human-attention:requested";
export const HUMAN_ATTENTION_RESOLVED = "human-attention:resolved";

type DialogKind = "select" | "confirm" | "input" | "editor" | "custom";

interface PiLike {
  events: { emit(name: string, data: unknown): void };
  on(event: string, handler: (event: unknown, ctx: any) => unknown): void;
}

export interface MoshiAttentionClient {
  requestAttention(request: AttentionRequest, ctx: any): void | Promise<void>;
  resolveAttention(request: AttentionRequest, ctx: any): void | Promise<void>;
}

interface InstallOptions {
  moshi?: false | MoshiAttentionClient;
}

export interface AttentionRequest {
  id: string;
  kind: DialogKind;
  title?: string;
}

export type MoshiEnvelope = Record<string, unknown>;
export type MoshiEnvelopeSender = (envelope: MoshiEnvelope) => void | Promise<void>;

function moshiSocketPath(): string {
  if (process.env.MOSHI_SOCKET_PATH) return process.env.MOSHI_SOCKET_PATH;
  if (process.platform === "darwin") {
    return join(homedir(), "Library", "Application Support", "Moshi", "moshi-hook.sock");
  }
  if (process.env.XDG_RUNTIME_DIR) return join(process.env.XDG_RUNTIME_DIR, "moshi-hook.sock");
  return "/tmp/moshi-hook.sock";
}

export function createMoshiEnvelopeSender(
  createConnection: typeof nodeCreateConnection = nodeCreateConnection,
  socketPath = moshiSocketPath(),
): MoshiEnvelopeSender {
  return (envelope) => {
    try {
      const socket = createConnection({ path: socketPath });
      socket.setNoDelay(true);
      socket.once("error", () => socket.destroy());
      socket.once("connect", () => {
        socket.write(`${JSON.stringify(envelope)}\n`);
        socket.end();
      });
      socket.on("data", () => {});
      socket.setTimeout?.(1000, () => socket.destroy());
      socket.unref?.();
    } catch {
      // Moshi is optional and must never interrupt the underlying Pi dialog.
    }
  };
}

function callString(target: unknown, method: string): string {
  if (!target || typeof target !== "object") return "";
  const fn = (target as Record<string, unknown>)[method];
  if (typeof fn !== "function") return "";
  try {
    return String(fn.call(target) ?? "");
  } catch {
    return "";
  }
}

function moshiEnvelopeContext(ctx: any): MoshiEnvelope {
  const usage = typeof ctx?.getContextUsage === "function" ? ctx.getContextUsage() : undefined;
  const usedPercent = typeof usage?.percent === "number" && Number.isFinite(usage.percent)
    ? usage.percent
    : undefined;
  const cwd = typeof ctx?.cwd === "string" ? ctx.cwd : process.cwd();
  const terminalKind = process.env.TMUX
    ? "tmux"
    : process.env.HERDR_ENV === "1"
      ? "herdr"
      : process.env.ZELLIJ || process.env.ZELLIJ_SESSION_NAME
        ? "zellij"
        : "shell";
  return {
    type: "session.update",
    source: "pi",
    sessionId: callString(ctx?.sessionManager, "getSessionId") || "pi",
    cwd,
    projectName: basename(cwd),
    terminalKind,
    tmuxPane: process.env.TMUX_PANE ?? "",
    zellijSession: process.env.ZELLIJ_SESSION_NAME ?? "",
    zellijPane: process.env.ZELLIJ_PANE_ID ?? "",
    herdrSession: process.env.HERDR_SESSION ?? "",
    herdrPane: process.env.HERDR_PANE_ID ?? "",
    herdrWorkspaceId: process.env.HERDR_WORKSPACE_ID ?? "",
    herdrTabId: process.env.HERDR_TAB_ID ?? "",
    modelName: typeof ctx?.model?.id === "string" ? ctx.model.id : "",
    requestedAt: new Date().toISOString(),
    contextRemaining: usedPercent === undefined
      ? undefined
      : Math.max(1, Math.min(100, Math.round(100 - usedPercent))),
  };
}

export function createMoshiAttentionClient(send: MoshiEnvelopeSender): MoshiAttentionClient {
  return {
    requestAttention(request, ctx) {
      return send({
        ...moshiEnvelopeContext(ctx),
        eventName: HUMAN_ATTENTION_REQUESTED,
        category: "approval_required",
        title: "Pi needs input",
        subtitle: "Answer in terminal",
        message: request.title ?? "Pi needs your input",
      });
    },
    resolveAttention(_request, ctx) {
      return send({
        ...moshiEnvelopeContext(ctx),
        eventName: HUMAN_ATTENTION_RESOLVED,
        category: "",
        title: "",
        subtitle: "",
        message: "",
      });
    },
  };
}

export function installHumanAttention(pi: PiLike, options: InstallOptions = {}): void {
  let restore: (() => void) | undefined;
  let activeCount = 0;
  let activeRequest: AttentionRequest | undefined;
  let activeContext: any;
  const moshi = options.moshi === false
    ? undefined
    : options.moshi ?? createMoshiAttentionClient(createMoshiEnvelopeSender());

  function notifyMoshi(action: "requestAttention" | "resolveAttention", request: AttentionRequest, ctx: any) {
    if (!moshi) return;
    try {
      void Promise.resolve(moshi[action](request, ctx)).catch(() => {});
    } catch {
      // Attention notifications must never prevent the underlying Pi dialog.
    }
  }

  function beginAttention(kind: DialogKind, args: unknown[], ctx: any): AttentionRequest {
    activeCount += 1;
    if (activeRequest) return activeRequest;

    activeRequest = {
      id: randomUUID(),
      kind,
      title: kind !== "custom" && typeof args[0] === "string" ? args[0] : undefined,
    };
    activeContext = ctx;
    pi.events.emit(HUMAN_ATTENTION_REQUESTED, activeRequest);
    notifyMoshi("requestAttention", activeRequest, ctx);
    pi.events.emit("herdr:blocked", {
      active: true,
      label: activeRequest.title ?? "Waiting for user input",
    });
    return activeRequest;
  }

  function clearAttention(request = activeRequest): void {
    if (!request || activeRequest !== request) return;
    const resolvedContext = activeContext;
    activeCount = 0;
    activeRequest = undefined;
    activeContext = undefined;
    pi.events.emit(HUMAN_ATTENTION_RESOLVED, request);
    notifyMoshi("resolveAttention", request, resolvedContext);
    pi.events.emit("herdr:blocked", { active: false });
  }

  function endAttention(request: AttentionRequest): void {
    activeCount = Math.max(0, activeCount - 1);
    if (activeCount === 0) clearAttention(request);
  }

  pi.on("session_start", (_event, ctx) => {
    const ui = ctx.ui as Record<string, any>;
    const originals = new Map<DialogKind, (...args: unknown[]) => unknown>();

    for (const kind of ["select", "confirm", "input", "editor", "custom"] as const) {
      if (typeof ui[kind] !== "function") continue;
      const original = ui[kind].bind(ui);
      originals.set(kind, original);

      ui[kind] = async (...args: unknown[]) => {
        const request = beginAttention(kind, args, ctx);
        try {
          return await original(...args);
        } finally {
          endAttention(request);
        }
      };
    }

    restore = () => {
      for (const [kind, original] of originals) {
        ui[kind] = original;
      }
    };
  });

  pi.on("session_shutdown", () => {
    clearAttention();
    restore?.();
    restore = undefined;
  });
}

export default function humanAttention(pi: ExtensionAPI): void {
  installHumanAttention(pi);
}
