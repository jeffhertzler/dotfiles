import type { ExtensionAPI, SessionEntry } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
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
}

interface FeedbackComment {
  id: string;
  body: string;
  kind?: string;
  startLine: number;
  startCol?: number;
  endLine: number;
  endCol?: number;
  selection?: string;
  quotedText?: string[];
}

interface FeedbackPayload {
  schemaVersion: 1;
  piSessionId?: string;
  assistantMessageId: string;
  sourcePath: string;
  submittedAt: string;
  comments: FeedbackComment[];
}

function assistantMarkdown(entry: SessionEntry): AssistantCapture | undefined {
  if (entry.type !== "message" || entry.message.role !== "assistant") return undefined;

  const markdown = entry.message.content
    .filter((block): block is { type: "text"; text: string } => block.type === "text")
    .map((block) => block.text)
    .join("\n\n")
    .trimEnd();
  if (!markdown) return undefined;
  return { entryId: entry.id, markdown };
}

export function collectAssistantCaptures(entries: SessionEntry[]): AssistantCapture[] {
  const captures: AssistantCapture[] = [];
  for (const entry of entries) {
    const capture = assistantMarkdown(entry);
    if (capture) captures.push(capture);
  }
  return captures;
}

function assistantChoiceLabel(capture: AssistantCapture, position: number | undefined): string {
  const preview = capture.markdown.replace(/\s+/g, " ").trim().slice(0, 100);
  const location = position === 0
    ? "Latest response"
    : position === undefined
      ? "Other branch"
      : `${position} response${position === 1 ? "" : "s"} back`;
  return `${location} · ${preview} [${capture.entryId}]`;
}

function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]+/g, "-").slice(0, 100);
}

function writeJsonAtomically(path: string, value: unknown): void {
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

function lineRange(comment: FeedbackComment): string {
  const start = comment.startCol ? `L${comment.startLine}:C${comment.startCol}` : `L${comment.startLine}`;
  const end = comment.endCol ? `L${comment.endLine}:C${comment.endCol}` : `L${comment.endLine}`;
  return start === end ? start : `${start}-${end}`;
}

function quoteLines(lines: string[] | undefined): string[] {
  if (!lines || lines.length === 0) return [];
  return lines.map((line) => `> ${line || " "}`);
}

function buildPrompt(feedback: FeedbackPayload): string {
  const out = [
    "# Feedback on your selected response",
    "",
    "I added line-specific feedback to a selected assistant response. Address each comment below.",
    `Assistant response ID: \`${feedback.assistantMessageId}\``,
  ];

  for (const comment of feedback.comments) {
    out.push("", `## ${comment.id} — ${lineRange(comment)}`);
    const quoted = quoteLines(comment.quotedText);
    if (quoted.length > 0) out.push("", ...quoted);
    out.push("", comment.body);
  }

  return `${out.join("\n")}\n\n`;
}

function parseFeedback(path: string, metadata: FeedbackMetadata): FeedbackPayload {
  const parsed: unknown = JSON.parse(readFileSync(path, "utf8"));
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("Neovim produced invalid feedback");
  }
  const feedback = parsed as Partial<FeedbackPayload>;
  if (
    feedback.schemaVersion !== 1 ||
    feedback.assistantMessageId !== metadata.assistantMessageId ||
    !Array.isArray(feedback.comments) ||
    feedback.comments.length === 0
  ) {
    throw new Error("Neovim produced incomplete feedback");
  }
  for (const comment of feedback.comments) {
    if (
      typeof comment !== "object" ||
      comment === null ||
      typeof comment.id !== "string" ||
      typeof comment.body !== "string" ||
      typeof comment.startLine !== "number" ||
      typeof comment.endLine !== "number"
    ) {
      throw new Error("Neovim produced an invalid feedback comment");
    }
  }
  return feedback as FeedbackPayload;
}

async function withoutAttentionNotifications<T>(
  pi: ExtensionAPI,
  action: () => Promise<T>,
): Promise<T> {
  pi.events.emit("human-attention:notifications-suppressed", { active: true });
  try {
    return await action();
  } finally {
    pi.events.emit("human-attention:notifications-suppressed", { active: false });
  }
}

function launchNeovim(
  metadataPath: string,
  sourcePath: string,
  feedbackStatePath: string,
): number | null {
  const executable = process.env.PI_FEEDBACK_NVIM || "nvim";
  const result = spawnSync(
    executable,
    [sourcePath, "-c", "lua require('agent_review.feedback').attach()"],
    {
      stdio: "inherit",
      env: {
        ...process.env,
        PI_FEEDBACK_METADATA: metadataPath,
        NVIM_AGENT_REVIEW_STATE: feedbackStatePath,
      },
    },
  );
  if (result.error) throw result.error;
  return result.status;
}

export default function feedbackExtension(pi: ExtensionAPI) {
  pi.registerCommand("feedback", {
    description: "Choose an assistant response from the session tree and annotate it in Neovim; use /feedback clear to remove drafts",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("Feedback requires interactive mode", "error");
        return;
      }

      const action = args.trim();
      if (action !== "" && action !== "clear") {
        ctx.ui.notify("Usage: /feedback [clear]", "warning");
        return;
      }

      const sessionId = ctx.sessionManager.getSessionId();
      const sessionFeedbackDirectory = join(
        ctx.sessionManager.getSessionDir(),
        "feedback",
        safeSegment(sessionId),
      );
      if (action === "clear") {
        rmSync(sessionFeedbackDirectory, { recursive: true, force: true });
        ctx.ui.notify("Cleared saved feedback drafts", "info");
        return;
      }

      await ctx.waitForIdle();
      const captures = collectAssistantCaptures(ctx.sessionManager.getEntries());
      const branchCaptures = collectAssistantCaptures(ctx.sessionManager.getBranch()).reverse();
      const branchCaptureIds = new Set(branchCaptures.map((capture) => capture.entryId));
      const orderedCaptures = [
        ...branchCaptures,
        ...captures.filter((capture) => !branchCaptureIds.has(capture.entryId)).reverse(),
      ];
      if (captures.length === 0) {
        ctx.ui.notify("No assistant response found for feedback", "warning");
        return;
      }

      let capture: AssistantCapture | undefined;
      if (orderedCaptures.length === 1) {
        capture = orderedCaptures[0];
      } else {
        const choices = orderedCaptures.map((candidate) => {
          const position = branchCaptures.findIndex((item) => item.entryId === candidate.entryId);
          return {
            capture: candidate,
            label: assistantChoiceLabel(candidate, position === -1 ? undefined : position),
          };
        });
        const selectedLabel = await withoutAttentionNotifications(pi, () => ctx.ui.select(
          "Choose assistant response from the session tree",
          choices.map((choice) => choice.label),
        ));
        if (!selectedLabel) return;
        capture = choices.find((choice) => choice.label === selectedLabel)?.capture;
      }
      if (!capture) {
        ctx.ui.notify("The selected assistant response is unavailable", "warning");
        return;
      }

      const feedbackDirectory = join(sessionFeedbackDirectory, safeSegment(capture.entryId));
      const sourcePath = join(feedbackDirectory, "source.md");
      const metadataPath = join(feedbackDirectory, "metadata.json");
      const feedbackPath = join(feedbackDirectory, "feedback.json");
      const feedbackStatePath = join(feedbackDirectory, "annotations.json");
      mkdirSync(feedbackDirectory, { recursive: true, mode: 0o700 });
      rmSync(feedbackPath, { force: true });
      writeFileSync(sourcePath, `${capture.markdown}\n`, { encoding: "utf8", mode: 0o600 });

      const metadata: FeedbackMetadata = {
        schemaVersion: 1,
        piSessionId: sessionId,
        assistantMessageId: capture.entryId,
        sessionFile: ctx.sessionManager.getSessionFile(),
        createdAt: new Date().toISOString(),
        feedbackDirectory,
        sourcePath,
        feedbackPath,
      };
      writeJsonAtomically(metadataPath, metadata);

      let exitStatus: number | null | undefined;
      try {
        exitStatus = await withoutAttentionNotifications(pi, () =>
          ctx.ui.custom<number | null>((tui, _theme, _keybindings, done) => {
            tui.stop();
            process.stdout.write("\x1b[2J\x1b[H");
            let status: number | null = null;
            try {
              status = launchNeovim(metadataPath, sourcePath, feedbackStatePath);
            } finally {
              tui.start();
              tui.requestRender(true);
            }
            done(status);
            return { render: () => [], invalidate: () => {} };
          }),
        );
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`Failed to open feedback: ${message}`, "error");
        return;
      }

      if (!existsSync(feedbackPath)) {
        if (exitStatus && exitStatus !== 0) {
          ctx.ui.notify(`Neovim exited with status ${exitStatus}`, "warning");
        } else if (existsSync(feedbackStatePath)) {
          ctx.ui.notify("Feedback draft kept", "info");
        } else {
          ctx.ui.notify("Feedback discarded", "info");
        }
        return;
      }

      try {
        const feedback = parseFeedback(feedbackPath, metadata);
        ctx.ui.setEditorText(buildPrompt(feedback));
        rmSync(feedbackDirectory, { recursive: true, force: true });
        ctx.ui.notify(
          `Staged and cleared ${feedback.comments.length} feedback comment${feedback.comments.length === 1 ? "" : "s"}`,
          "info",
        );
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(message, "error");
      }
    },
  });
}
