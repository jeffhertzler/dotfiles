import {
  closeSync, constants, fstatSync, fsyncSync, lstatSync, openSync, readFileSync,
  readdirSync, readSync, realpathSync, renameSync, unlinkSync, writeFileSync,
} from "node:fs";
import { randomUUID } from "node:crypto";
import { dirname, isAbsolute, join, resolve } from "node:path";

export interface SubagentRetentionOptions {
  artifactRoot: string;
  sessionRoot: string;
  retentionDays: number;
  now: number;
  dryRun?: boolean;
}

export interface SubagentRetentionResult {
  eligible: string[];
  expired: string[];
  warnings: string[];
}

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const TERMINAL = new Set(["completed", "failed", "cancelled"]);
const DAY = 86_400_000;
type Json = Record<string, any>;
type ParentLog = { id: string; entries: Map<string, Json> };

function object(value: unknown): value is Json {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function timestamp(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

// realpath equality rejects symlinks in ancestors as well as the final component.
function inspect(path: string, kind: "file" | "directory") {
  const stat = lstatSync(path, { throwIfNoEntry: false });
  if (!stat) return undefined;
  if (stat.isSymbolicLink() || realpathSync(path) !== path ||
      (kind === "file" ? !stat.isFile() : !stat.isDirectory())) {
    throw new Error(`Unsafe ${kind}: ${path}`);
  }
  return stat;
}

function openFile(path: string): number {
  if (!inspect(path, "file")) throw new Error(`Missing file: ${path}`);
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  if (!fstatSync(fd).isFile()) {
    closeSync(fd);
    throw new Error(`Not a regular file: ${path}`);
  }
  return fd;
}

function readText(path: string): string {
  const fd = openFile(path);
  try { return readFileSync(fd, "utf8"); }
  finally { closeSync(fd); }
}

function syncDirectory(path: string): void {
  const fd = openSync(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { fsyncSync(fd); }
  finally { closeSync(fd); }
}

function saveReceipt(path: string, receipt: Json): void {
  inspect(dirname(path), "directory");
  inspect(path, "file");
  const temporary = join(dirname(path), `.task-${randomUUID()}.tmp`);
  try {
    const fd = openSync(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    try {
      writeFileSync(fd, JSON.stringify(receipt) + "\n");
      fsyncSync(fd);
    } finally { closeSync(fd); }
    renameSync(temporary, path);
    syncDirectory(dirname(path));
  } finally {
    try { unlinkSync(temporary); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
}

function readParent(path: string): ParentLog {
  const lines = readText(path).trimEnd().split("\n");
  const header = JSON.parse(lines.shift() ?? "");
  if (!object(header) || header.type !== "session" || typeof header.id !== "string") {
    throw new Error(`Invalid parent session header: ${path}`);
  }
  const entries = new Map<string, Json>();
  for (const line of lines) {
    const entry = JSON.parse(line);
    if (!object(entry) || entry.type === "session" || typeof entry.type !== "string" ||
        typeof entry.id !== "string" || !entry.id || entries.has(entry.id) ||
        (entry.parentId !== null && (typeof entry.parentId !== "string" || !entries.has(entry.parentId)))) {
      throw new Error(`Invalid parent session tree: ${path}`);
    }
    entries.set(entry.id, entry);
  }
  return { id: header.id, entries };
}

function hasReport(content: unknown): boolean {
  return typeof content === "string" ? content.trim().length > 0
    : Array.isArray(content) && content.some((part) =>
      part?.type === "text" && typeof part.text === "string" && part.text.trim().length > 0);
}

function acknowledged(parent: ParentLog, task: Json): boolean {
  if (parent.id !== task.parentSessionId) throw new Error("Parent session header does not match ownership");
  for (const entry of parent.entries.values()) {
    const message = entry.type === "message" ? entry.message : undefined;
    const custom = entry.type === "custom_message" && entry.customType === "subagent_result" &&
      entry.details?.id === task.id && TERMINAL.has(entry.details?.status) && hasReport(entry.content);
    const waited = message?.role === "toolResult" && message.toolName === "subagent_wait" &&
      message.isError === false && message.details?.id === task.id &&
      TERMINAL.has(message.details?.status) && hasReport(message.content);
    if (!custom && !waited) continue;
    // readParent checked every link, including the path back to null.
    let ancestor = entry.parentId;
    while (ancestor !== null && ancestor !== task.parentEntryId) {
      ancestor = parent.entries.get(ancestor)!.parentId;
    }
    if (ancestor === task.parentEntryId) return true;
  }
  return false;
}

function validOwnership(task: Json, id: string, directory: string): boolean {
  return task.id === id && task.agentSessionId === id &&
    typeof task.parentSessionId === "string" && task.parentSessionId.length > 0 && task.parentSessionId !== id &&
    (task.parentEntryId === null || (typeof task.parentEntryId === "string" && task.parentEntryId.length > 0)) &&
    task.resultDirectory === directory && task.resultFile === join(directory, "result.json") &&
    task.stateFile === join(directory, "state.json") &&
    typeof task.parentSessionFile === "string" && isAbsolute(task.parentSessionFile) &&
    resolve(task.parentSessionFile) === task.parentSessionFile &&
    ![task.resultFile, task.stateFile, join(directory, "task.json")].includes(task.parentSessionFile) &&
    (task.retentionEligibleAt === undefined || timestamp(task.retentionEligibleAt)) &&
    (task.expiredAt === undefined || (timestamp(task.expiredAt) && timestamp(task.retentionEligibleAt)));
}

// A child transcript can be huge. Only its first line establishes session identity.
function childHeaderId(path: string): unknown {
  const fd = openFile(path);
  try {
    const buffer = Buffer.alloc(64 * 1024);
    let length = 0;
    while (length < buffer.length) {
      const count = readSync(fd, buffer, length, Math.min(4096, buffer.length - length), null);
      length += count;
      const newline = buffer.subarray(0, length).indexOf(10);
      if (newline !== -1 || count === 0) {
        const header = JSON.parse(buffer.subarray(0, newline === -1 ? length : newline).toString("utf8"));
        if (!object(header) || header.type !== "session") throw new Error(`Invalid child session header: ${path}`);
        return header.id;
      }
    }
    throw new Error(`Child session header exceeds 64 KiB: ${path}`);
  } finally { closeSync(fd); }
}

function childFiles(sessionRoot: string, id: string, parentFile: string): string[] {
  if (!inspect(sessionRoot, "directory")) return [];
  const files: string[] = [];
  for (const folder of readdirSync(sessionRoot, { withFileTypes: true })) {
    // A linked cwd directory could conceal a matching history. Do not prune around it.
    if (folder.isSymbolicLink()) throw new Error(`Symlink in session store: ${join(sessionRoot, folder.name)}`);
    if (!folder.isDirectory()) continue;
    const directory = join(sessionRoot, folder.name);
    inspect(directory, "directory");
    for (const name of readdirSync(directory)) {
      if (!name.endsWith(`_${id}.jsonl`) || name === `_${id}.jsonl`) continue;
      const file = join(directory, name);
      if (file === parentFile) throw new Error("Child history is also the parent session");
      if (childHeaderId(file) !== id) throw new Error(`Child session header does not match Task: ${file}`);
      files.push(file);
    }
  }
  return files.sort();
}

/** Sweep only closed terminal Tasks with an acknowledgement saved by their owning parent. */
export function sweepSubagentRetention(options: SubagentRetentionOptions): SubagentRetentionResult {
  const { retentionDays, now, dryRun = false } = options;
  if (!Number.isFinite(retentionDays) || !Number.isInteger(retentionDays) || retentionDays < 0) {
    throw new Error("retentionDays must be a finite nonnegative integer");
  }
  const result: SubagentRetentionResult = { eligible: [], expired: [], warnings: [] };
  if (retentionDays === 0) return result;
  if (!timestamp(now)) throw new Error("now must be a finite nonnegative timestamp");
  const artifactRoot = resolve(options.artifactRoot);
  const sessionRoot = resolve(options.sessionRoot);
  const age = retentionDays * DAY;
  const parents = new Map<string, ParentLog | Error>();
  try {
    if (!inspect(artifactRoot, "directory")) return result;
    const ids = readdirSync(artifactRoot).filter((id) => UUID.test(id)).sort();
    const referencedParents = new Set<string>();
    for (const id of ids) {
      try {
        const file = join(artifactRoot, id, "task.json");
        if (!inspect(file, "file")) continue;
        const task = JSON.parse(readText(file));
        if (object(task) && task.id === id && typeof task.parentSessionId === "string" && task.parentSessionId !== id) {
          referencedParents.add(task.parentSessionId);
        }
      } catch {
        // The task pass below reports unreadable records without following links.
      }
    }
    for (const id of ids) {
      let removedFiles = false;
      try {
        const directory = join(artifactRoot, id);
        if (!inspect(directory, "directory")) continue;
        const manifestFile = join(directory, "task.json");
        if (!inspect(manifestFile, "file")) continue;
        const task = JSON.parse(readText(manifestFile));
        if (!object(task)) throw new Error("Invalid task receipt");
        if (!TERMINAL.has(task.status) || task.cleaned !== true) continue;
        // A human may reopen a former child and use it to launch another Task.
        // Its conversation is now parent history, even though the original Task ended.
        if (referencedParents.has(id)) continue;
        // Old manifests are enriched by the owning parent, not by this sweep.
        if (task.parentSessionFile === undefined) continue;
        if (!validOwnership(task, id, directory)) throw new Error("Invalid task ownership or retention timestamps");
        let parent = parents.get(task.parentSessionFile);
        if (!parent) {
          try { parent = readParent(task.parentSessionFile); }
          catch (error) { parent = error instanceof Error ? error : new Error(String(error)); }
          parents.set(task.parentSessionFile, parent);
        }
        if (parent instanceof Error) throw parent;
        if (!acknowledged(parent, task)) continue;
        inspect(task.resultFile, "file");
        inspect(task.stateFile, "file");
        result.eligible.push(id);
        if (task.retentionEligibleAt === undefined) {
          if (!dryRun) saveReceipt(manifestFile, { ...task, retentionEligibleAt: now });
          continue;
        }
        if (now - task.retentionEligibleAt < age) continue;
        const children = childFiles(sessionRoot, id, task.parentSessionFile);
        const files = [task.resultFile, task.stateFile, ...children].flatMap((path: string) => {
          const stat = inspect(path, "file");
          return stat ? [{ path, stat }] : [];
        });
        // State is transient, but a newly written Result or resumed Agent resets the safety window.
        if (files.some(({ path, stat }) => path !== task.stateFile && now - stat.mtimeMs < age)) continue;
        if (task.expiredAt !== undefined && files.length === 0) continue;
        if (!dryRun) {
          // The receipt must survive a crash before the first unlink. Repeated sweeps retry leftovers.
          if (task.expiredAt === undefined) saveReceipt(manifestFile, { ...task, expiredAt: now });
          else syncDirectory(directory);
          for (const { path, stat } of files) {
            const current = inspect(path, "file");
            if (!current) continue;
            if (current.ino !== stat.ino || current.dev !== stat.dev || current.mtimeMs !== stat.mtimeMs || current.size !== stat.size) {
              throw new Error(`File changed during retention sweep: ${path}`);
            }
            unlinkSync(path);
            removedFiles = true;
          }
        }
        result.expired.push(id);
      } catch (error) {
        if (removedFiles) result.expired.push(id);
        result.warnings.push(`${id}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
  } catch (error) {
    result.warnings.push(error instanceof Error ? error.message : String(error));
  }
  return result;
}
