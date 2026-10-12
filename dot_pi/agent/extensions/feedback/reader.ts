import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { createConnection } from "node:net";
import { dirname, join } from "node:path";

export interface PaneReaderHandle {
  kind?: "pane"; // Unlabelled handles from the original launcher remain valid.
  paneId: string;
  terminalId: string;
  socketPath: string;
}

export interface NvimReaderHandle {
  kind: "nvim";
  server: string;
  cataloguePath: string;
  paneId?: string;
  terminalId?: string;
  socketPath?: string;
}

export type ReaderHandle = PaneReaderHandle | NvimReaderHandle;
export interface ReaderRequest { cataloguePath: string; feedbackStatePath: string; cwd: string }
export interface FeedbackReader<H extends ReaderHandle = ReaderHandle> {
  isOpen(handle: H): Promise<boolean>;
  focus(handle: H): Promise<void>;
  open(request: ReaderRequest): Promise<H>;
}

type Executor = Pick<ExtensionAPI, "exec">;
type Environment = Record<string, string | undefined>;

async function herdr(pi: Executor, args: string[]) {
  const result = await pi.exec("herdr", args, { timeout: 10_000 });
  if (result.code !== 0) {
    const error = new Error(`herdr ${args.slice(0, 2).join(" ")}: ${result.stderr || result.stdout}`);
    try { (error as any).code = JSON.parse(result.stderr || result.stdout).error?.code; } catch { /* plain CLI error */ }
    throw error;
  }
  return result.stdout.trim() ? JSON.parse(result.stdout).result : undefined;
}

// The socket API supports exact pane focus, unlike the directional CLI. It also
// selects the containing tab. Never close or otherwise manage a reused editor.
async function focusPane(socketPath: string, paneId: string): Promise<void> {
  if (!socketPath) throw new Error("Herdr socket path is unavailable; cannot focus the reader pane");
  await new Promise<void>((resolve, reject) => {
    const id = randomUUID();
    const socket = createConnection(socketPath);
    let buffer = "";
    const finish = (error?: Error) => { socket.destroy(); error ? reject(error) : resolve(); };
    socket.setTimeout(3000, () => finish(new Error("Timed out focusing the Neovim pane")));
    socket.once("error", finish);
    socket.once("end", () => finish(new Error("Herdr disconnected before confirming pane focus")));
    socket.once("connect", () => socket.write(`${JSON.stringify({ id, method: "pane.focus", params: { pane_id: paneId } })}\n`));
    socket.on("data", (chunk) => {
      buffer += chunk.toString();
      if (buffer.length > 64 * 1024) return finish(new Error("Oversized Herdr focus response"));
      while (buffer.includes("\n")) {
        const end = buffer.indexOf("\n");
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        try {
          const response = JSON.parse(line);
          if (response.id !== id) continue;
          finish(response.error ? new Error(response.error.message ?? "Could not focus Neovim") : undefined);
          return;
        } catch (error) { finish(error as Error); return; }
      }
    });
  });
}

function shellQuote(value: string): string { return `'${value.replace(/'/g, `'\\''`)}'`; }

export function createHerdrFeedbackReader(pi: Executor, env: Environment = process.env): FeedbackReader<PaneReaderHandle> {
  return {
    async isOpen(handle) {
      if (handle.socketPath !== (env.HERDR_SOCKET_PATH ?? "")) {
        throw new Error("This feedback reader belongs to another Herdr session; close it there before reopening here");
      }
      try {
        const result = await herdr(pi, ["pane", "get", handle.paneId]);
        return result?.pane?.terminal_id === handle.terminalId;
      } catch (error) {
        if ((error as any).code === "pane_not_found") return false;
        throw error;
      }
    },
    async focus(handle) {
      if (handle.socketPath !== (env.HERDR_SOCKET_PATH ?? "")) {
        throw new Error("This feedback reader belongs to another Herdr session");
      }
      await focusPane(handle.socketPath, handle.paneId);
    },
    async open(request) {
      if (env.HERDR_ENV !== "1" || !env.HERDR_PANE_ID) {
        throw new Error("The nonblocking feedback reader requires Herdr when no existing Neovim is available; it will not take over Pi's terminal");
      }
      const layout = await herdr(pi, ["pane", "layout", "--current"]);
      const caller = layout?.layout?.panes?.find((pane: any) => pane.pane_id === env.HERDR_PANE_ID);
      const direction = (caller?.rect?.width ?? 0) >= 140 ? "right" : "down";
      const created = await herdr(pi, ["pane", "split", "--current", "--direction", direction, "--cwd", request.cwd, "--focus"]);
      const pane = created?.pane;
      if (typeof pane?.pane_id !== "string" || typeof pane?.terminal_id !== "string") throw new Error("Herdr returned no reader pane identity");
      const handle = { paneId: pane.pane_id, terminalId: pane.terminal_id, socketPath: env.HERDR_SOCKET_PATH ?? "" };
      // Keep the standalone editor's unused normal context private too, without
      // aliasing any feedback context or the user's ordinary annotation store.
      const launch = ["env", `PI_FEEDBACK_CATALOG=${request.cataloguePath}`, `NVIM_AGENT_REVIEW_STATE=${join(dirname(request.cataloguePath), "reader-state.json")}`,
        env.PI_FEEDBACK_NVIM || "nvim", "-c", "lua require('agent_review.feedback_reader').open()"].map(shellQuote).join(" ");
      const script = `${launch}; feedback_exit=$?; if [ "$feedback_exit" -eq 0 ]; then herdr pane close ${shellQuote(handle.paneId)}; else printf '\\nFeedback reader failed (%s). Close this pane before retrying.\\n' "$feedback_exit"; fi`;
      try { await herdr(pi, ["pane", "run", handle.paneId, script]); }
      catch (error) { (error as any).readerHandle = handle; throw error; }
      return handle;
    },
  };
}

// Payloads are data, not interpolated Lua or Ex commands. Probe is read-only and
// rejects editors with the pre-context-isolation plugin already loaded.
const probe = `return {version=require('agent_review').feedback_context_version or 0, paneId=vim.env.HERDR_PANE_ID, socketPath=vim.env.HERDR_SOCKET_PATH, dedicated=vim.env.PI_FEEDBACK_CATALOG ~= nil}`;
function expression(lua: string): string {
  const encoded = Buffer.from(lua).toString("base64");
  return `luaeval("vim.json.encode(assert(loadstring(vim.base64.decode([[${encoded}]])))())")`;
}

async function nvim(pi: Executor, server: string, lua: string): Promise<any | undefined> {
  const result = await pi.exec("nvim", ["--headless", "--server", server, "--remote-expr", expression(lua)], { timeout: 5000 });
  if (result.killed) throw new Error("Neovim did not answer in time; no second editor was opened");
  if (result.code !== 0) {
    if (/E247:.*connection refused/is.test(result.stderr)) return undefined;
    throw new Error(`Neovim RPC failed: ${result.stderr || result.stdout}`);
  }
  try { return JSON.parse(result.stdout); }
  catch { throw new Error("Neovim returned an invalid response; no second editor was opened"); }
}

async function remote(pi: Executor, handle: NvimReaderHandle, action: "open" | "focus" | "status", feedbackStatePath?: string) {
  const request = Buffer.from(JSON.stringify({ action, cataloguePath: handle.cataloguePath, feedbackStatePath })).toString("base64");
  const reply = await nvim(pi, handle.server, `if require('agent_review').feedback_context_version ~= 1 then return {ok=false,error='Restart Neovim to load feedback context isolation'} end; return require('agent_review.feedback_reader').remote(vim.json.decode(vim.base64.decode([[${request}]])))`);
  if (reply === undefined) return undefined;
  if (!reply || reply.ok !== true || typeof reply.open !== "boolean") throw new Error(reply?.error ?? "Invalid feedback reader response");
  return reply;
}

export function createFeedbackReader(pi: Executor, env: Environment = process.env,
  options: { fallback?: FeedbackReader<PaneReaderHandle> } = {}): FeedbackReader {
  const fallback = options.fallback ?? createHerdrFeedbackReader(pi, env);
  const registry = env.XDG_RUNTIME_DIR ? join(env.XDG_RUNTIME_DIR, "herdr-nvim") : `/tmp/herdr-nvim-${process.getuid?.()}`;

  function checkSession(handle: NvimReaderHandle) {
    if (handle.socketPath && handle.socketPath !== env.HERDR_SOCKET_PATH) throw new Error("Feedback reader belongs to another Herdr session");
  }
  async function focus(handle: NvimReaderHandle) {
    checkSession(handle);
    const reply = await remote(pi, handle, "focus");
    if (!reply?.open) throw new Error("Feedback reader closed before it could be focused; run /feedback again");
    if (handle.paneId && handle.socketPath) {
      const pane = (await herdr(pi, ["pane", "get", handle.paneId]))?.pane;
      if (!pane || (handle.terminalId && pane.terminal_id !== handle.terminalId)) throw new Error("Neovim pane changed; switch to its editor manually");
      await focusPane(handle.socketPath, handle.paneId);
    }
  }
  async function discover(cataloguePath: string): Promise<NvimReaderHandle | undefined> {
    const explicit = env.NVIM_SERVER || env.NVIM;
    if (explicit) {
      const info = await nvim(pi, explicit, probe);
      if (!info) throw new Error("The requested Neovim server is unavailable; check NVIM_SERVER/NVIM");
      if (info.dedicated) throw new Error("The requested Neovim is a dedicated feedback reader, not a shared editor");
      if (info.version !== 1) throw new Error("Restart Neovim to load feedback context isolation");
      const handle: NvimReaderHandle = { kind: "nvim", server: explicit, cataloguePath, paneId: info.paneId, socketPath: info.socketPath };
      checkSession(handle);
      return handle;
    }
    if (env.HERDR_ENV !== "1" || !env.HERDR_WORKSPACE_ID) return undefined;
    const response = await herdr(pi, ["pane", "list", "--workspace", env.HERDR_WORKSPACE_ID]);
    if (!Array.isArray(response?.panes)) throw new Error("Invalid Herdr workspace response; cannot safely choose an editor");
    const candidates = await Promise.all(response.panes.map(async (pane: any) => {
      if (pane.workspace_id !== env.HERDR_WORKSPACE_ID || typeof pane.pane_id !== "string" || typeof pane.terminal_id !== "string") return undefined;
      let server: string;
      try { server = readFileSync(join(registry, `${pane.pane_id.replace(/[^A-Za-z0-9_.-]/g, "_")}.server`), "utf8").split(/\r?\n/)[0]; }
      catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw error; }
      if (!server) return undefined;
      const info = await nvim(pi, server, probe);
      if (!info || info.dedicated || info.paneId !== pane.pane_id || info.socketPath !== env.HERDR_SOCKET_PATH) return undefined;
      return { info, pane, server };
    }));
    const live = candidates.filter((item) => item !== undefined);
    const sameTab = live.filter((item) => item.pane.tab_id === env.HERDR_TAB_ID);
    const preferred = sameTab.length ? sameTab : live;
    if (!preferred.length) return undefined;
    if (preferred.length > 1) throw new Error("Multiple Neovim editors match this workspace. Set NVIM_SERVER to the intended socket; no extra editor was opened");
    const { info, pane, server } = preferred[0];
    if (info.version !== 1) throw new Error("Restart Neovim to load feedback context isolation");
    return { kind: "nvim", server, cataloguePath, paneId: pane.pane_id, terminalId: pane.terminal_id, socketPath: info.socketPath };
  }
  return {
    async isOpen(handle) {
      if (handle.kind !== "nvim") return fallback.isOpen(handle);
      checkSession(handle);
      return (await remote(pi, handle, "status"))?.open ?? false;
    },
    async focus(handle) {
      if (handle.kind !== "nvim") return fallback.focus(handle);
      await focus(handle);
    },
    async open(request) {
      const handle = await discover(request.cataloguePath);
      if (!handle) return fallback.open(request);
      try {
        const reply = await remote(pi, handle, "open", request.feedbackStatePath);
        if (!reply?.open) throw new Error("Neovim closed before opening feedback; run /feedback again");
        await focus(handle);
        return handle;
      } catch (error) {
        // An RPC timeout or focus failure does not prove open failed. Persist
        // the server+catalogue identity, never race it with a fallback process.
        (error as any).readerHandle = handle;
        throw error;
      }
    },
  };
}
