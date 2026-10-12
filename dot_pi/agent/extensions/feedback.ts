import type { ExtensionAPI, SessionEntry } from "@earendil-works/pi-coding-agent";
import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createFeedbackReader, type FeedbackReader, type ReaderHandle } from "./feedback/reader.ts";
export { createFeedbackReader, createHerdrFeedbackReader, type FeedbackReader, type ReaderHandle } from "./feedback/reader.ts";

export interface AssistantCapture {
  entryId: string;
  markdown: string;
}

interface FeedbackMetadata {
  schemaVersion: 1;
  piSessionId: string;
  assistantMessageId: string;
  sessionFile?: string;
  createdAt: string;
  feedbackDirectory: string;
  sourcePath: string;
  feedbackPath: string;
  reader: true;
}

interface ReaderMessage {
  entryId: string;
  title: string;
  prompt: string;
  timestamp: string;
  onBranch: boolean;
  finished: boolean;
  sourcePath: string;
  metadataPath: string;
  feedbackStatePath: string;
}

interface Catalogue {
  schemaVersion: 1;
  piSessionId: string;
  latestEntryId: string;
  messages: ReaderMessage[];
}

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function safeSegment(value: string): string {
  return /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$/.test(value) ? value : digest(value);
}

function writeJsonAtomically(path: string, value: unknown): void {
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  try {
    writeFileSync(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
    renameSync(temporaryPath, path);
  } finally {
    if (existsSync(temporaryPath)) unlinkSync(temporaryPath);
  }
}

function textContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.filter((part) => part?.type === "text" && typeof part.text === "string")
    .map((part) => part.text).join("\n\n");
}

export function collectAssistantCaptures(entries: SessionEntry[]): AssistantCapture[] {
  return entries.flatMap((entry) => {
    if (entry.type !== "message" || entry.message.role !== "assistant" ||
        entry.message.stopReason === "pending" || entry.message.stopReason === "deferred") return [];
    const markdown = textContent(entry.message.content).trimEnd();
    return markdown.trim() ? [{ entryId: entry.id, markdown }] : [];
  });
}

function shortText(text: string, length: number): string {
  return text.replace(/\s+/g, " ").trim().slice(0, length);
}

function sessionDirectory(ctx: any): string {
  return join(ctx.sessionManager.getSessionDir(), "feedback", safeSegment(ctx.sessionManager.getSessionId()));
}

function cataloguePath(ctx: any): string {
  return join(sessionDirectory(ctx), "catalogue.json");
}

function publishCatalogue(ctx: any): Catalogue {
  const entries: SessionEntry[] = ctx.sessionManager.getEntries();
  const branch: SessionEntry[] = ctx.sessionManager.getBranch();
  const byId = new Map(entries.map((entry) => [entry.id, entry]));
  const branchIds = new Set(branch.map((entry) => entry.id));
  const captures = collectAssistantCaptures(entries);
  const ordered = [
    ...captures.filter((capture) => branchIds.has(capture.entryId)).reverse(),
    ...captures.filter((capture) => !branchIds.has(capture.entryId)).reverse(),
  ];
  const piSessionId = ctx.sessionManager.getSessionId();
  const directory = sessionDirectory(ctx);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const messages = ordered.map((capture): ReaderMessage => {
    const entry = byId.get(capture.entryId)!;
    let ancestor = entry.parentId;
    let prompt = "";
    const seen = new Set<string>();
    while (ancestor && !seen.has(ancestor)) {
      seen.add(ancestor);
      const previous = byId.get(ancestor);
      if (!previous) break;
      if (previous.type === "message" && previous.message.role === "user") {
        prompt = shortText(textContent(previous.message.content), 240);
        break;
      }
      ancestor = previous.parentId;
    }
    const feedbackDirectory = join(directory, safeSegment(capture.entryId));
    const sourcePath = join(feedbackDirectory, "source.md");
    const metadataPath = join(feedbackDirectory, "metadata.json");
    mkdirSync(feedbackDirectory, { recursive: true, mode: 0o700 });
    // Source is an immutable snapshot. Never move existing annotation anchors.
    if (!existsSync(sourcePath)) {
      writeFileSync(sourcePath, `${capture.markdown}\n`, { encoding: "utf8", mode: 0o600, flag: "wx" });
    }
    const metadata: FeedbackMetadata = {
      schemaVersion: 1, piSessionId, assistantMessageId: capture.entryId,
      sessionFile: ctx.sessionManager.getSessionFile(), createdAt: entry.timestamp,
      feedbackDirectory, sourcePath, feedbackPath: join(feedbackDirectory, "feedback.json"), reader: true,
    };
    const oldMetadata = existsSync(metadataPath) ? JSON.parse(readFileSync(metadataPath, "utf8")) : undefined;
    if (oldMetadata && (oldMetadata.piSessionId !== piSessionId || oldMetadata.assistantMessageId !== capture.entryId)) {
      throw new Error("Feedback snapshot ownership does not match this conversation");
    }
    if (!oldMetadata?.reader) writeJsonAtomically(metadataPath, metadata);
    const snapshot = readFileSync(sourcePath, "utf8");
    const heading = snapshot.split("\n").find((line) => line.trim()) ?? "Assistant response";
    return {
      entryId: capture.entryId, title: shortText(heading.replace(/^\s*#{1,6}\s+/, ""), 120),
      prompt, timestamp: entry.timestamp, onBranch: branchIds.has(capture.entryId),
      finished: entry.type === "message" && entry.message.role === "assistant" && entry.message.stopReason === "stop",
      sourcePath, metadataPath, feedbackStatePath: join(feedbackDirectory, "annotations.json"),
    };
  });
  const catalogue: Catalogue = {
    schemaVersion: 1, piSessionId,
    latestEntryId: messages.find((message) => message.onBranch && message.finished)?.entryId ?? "",
    messages,
  };
  writeJsonAtomically(cataloguePath(ctx), catalogue);
  return catalogue;
}

function readHandle(directory: string): ReaderHandle | undefined {
  const path = join(directory, "reader.json");
  if (!existsSync(path)) return undefined;
  const value = JSON.parse(readFileSync(path, "utf8"));
  const valid = value?.kind === "nvim"
    ? typeof value.server === "string" && value.server.length > 0 && value.cataloguePath === join(directory, "catalogue.json") &&
      ["paneId", "terminalId", "socketPath"].every((key) => value[key] === undefined || typeof value[key] === "string")
    : value && (value.kind === undefined || value.kind === "pane") && typeof value.paneId === "string" &&
      typeof value.terminalId === "string" && typeof value.socketPath === "string";
  if (!valid) {
    throw new Error("Invalid feedback reader identity; refusing to open another editor or clear its files");
  }
  return value;
}

export function installFeedbackExtension(pi: ExtensionAPI, options: { reader?: FeedbackReader } = {}): void {
  const reader = options.reader ?? createFeedbackReader(pi);
  let launching = false;
  let lastRefreshError: string | undefined;
  const refresh = (_event: unknown, ctx: any) => {
    if (!existsSync(cataloguePath(ctx))) return;
    try {
      publishCatalogue(ctx);
      lastRefreshError = undefined;
    } catch (error) {
      const message = String(error);
      if (message !== lastRefreshError) ctx.ui.notify(`Feedback reader refresh failed: ${message}`, "warning");
      lastRefreshError = message;
    }
  };
  // turn_end is after session persistence. message_end runs before appendMessage.
  pi.on("turn_end", refresh);
  pi.on("agent_settled", refresh);
  pi.on("session_tree", refresh);
  pi.on("session_start", refresh);
  pi.registerCommand("feedback", {
    description: "Read replies in your workspace Neovim while Pi works, or open a reader pane if none exists. Submit in Neovim stages feedback through Agent Bridge. /feedback clear removes saved drafts.",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("Feedback requires interactive mode", "error");
        return;
      }
      const action = args.trim();
      if (!["", "clear"].includes(action)) {
        ctx.ui.notify("Usage: /feedback [clear]", "warning");
        return;
      }
      if (launching) {
        ctx.ui.notify("Feedback reader is already opening", "warning");
        return;
      }
      launching = true;
      const directory = sessionDirectory(ctx);
      const cwd = ctx.cwd;
      try {
        // Snapshot before any Herdr awaits. Session replacement must not redirect
        // an in-flight reader command into the new conversation's files.
        const catalogue = action === "" ? publishCatalogue(ctx) : undefined;
        const handle = readHandle(directory);
        const open = handle ? await reader.isOpen(handle) : false;
        if (action === "clear") {
          if (open) throw new Error("Close the feedback reader before clearing its drafts");
          rmSync(directory, { recursive: true, force: true });
          ctx.ui.notify("Cleared saved feedback drafts and snapshots", "info");
          return;
        }
        if (open && handle) {
          await reader.focus(handle);
          return;
        }
        const latest = catalogue!.messages.find((message) => message.entryId === catalogue!.latestEntryId);
        if (!latest) {
          ctx.ui.notify("No completed reply yet", "info");
          return;
        }
        try {
          const created = await reader.open({ cataloguePath: join(directory, "catalogue.json"), feedbackStatePath: latest.feedbackStatePath, cwd });
          writeJsonAtomically(join(directory, "reader.json"), created);
        } catch (error) {
          if ((error as any).readerHandle) writeJsonAtomically(join(directory, "reader.json"), (error as any).readerHandle);
          throw error;
        }
      } catch (error) {
        ctx.ui.notify(`Feedback: ${error instanceof Error ? error.message : String(error)}`, "error");
      } finally {
        launching = false;
      }
    },
  });
}

export default function feedbackExtension(pi: ExtensionAPI): void {
  installFeedbackExtension(pi);
}
