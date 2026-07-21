import { stripVTControlCharacters } from "node:util";

// Higher-priority segments are packed first. Lower-priority segments disappear
// cleanly as the terminal narrows instead of being clipped halfway through.
const priority = new Map([
  ["profile", 5],
  ["model", 10],
  ["thinking", 20],
  ["context", 30],
  ["billing", 40],
  ["io", 50],
  ["cache", 60],
  ["extensions", 70],
  ["branch", 80],
  ["cwd", 90],
]);

function visibleWidth(text) {
  return Array.from(stripVTControlCharacters(text)).length;
}

function truncateAnsi(text, width) {
  if (width <= 0) return "";

  const tokens = text.match(/\x1b\[[0-?]*[ -/]*[@-~]|[^\x1b]/g) ?? [];
  let result = "";
  let used = 0;
  for (const token of tokens) {
    if (token.startsWith("\x1b")) {
      result += token;
      continue;
    }
    if (used >= width) break;
    result += token;
    used += 1;
  }
  return `${result}\x1b[0m`;
}

function abbreviateDirectory(segment) {
  const characters = Array.from(segment);
  if (characters.length <= 1) return segment;
  if (characters[0] === ".") return `.${characters[1]}`;
  return characters[0];
}

function pathCandidates(path) {
  const prefix = path.startsWith("~/") ? "~/" : path.startsWith("/") ? "/" : "";
  const body = prefix === "~/" ? path.slice(2) : prefix === "/" ? path.slice(1) : path;
  const segments = body.split("/").filter(Boolean);
  if (segments.length <= 1) return [path];

  const candidates = [path];
  for (let shortened = 1; shortened < segments.length; shortened += 1) {
    const next = segments.map((segment, index) =>
      index < shortened && index < segments.length - 1 ? abbreviateDirectory(segment) : segment,
    );
    candidates.push(`${prefix}${next.join("/")}`);
  }
  candidates.push(`${prefix}…/${segments.at(-1)}`);
  return [...new Set(candidates)];
}

function fitCwd(styledText, maxWidth) {
  const path = stripVTControlCharacters(styledText);
  const start = styledText.indexOf(path);
  if (start === -1) return null;

  for (const candidate of pathCandidates(path)) {
    if (visibleWidth(candidate) > maxWidth) continue;
    return `${styledText.slice(0, start)}${candidate}${styledText.slice(start + path.length)}`;
  }
  return null;
}

export function renderBar(bar) {
  if (bar.position !== "footer") return null;

  const activeProfile = globalThis[Symbol.for("pi.active-profile")];
  const profilePart =
    typeof activeProfile === "string" && activeProfile.length > 0
      ? {
          key: "profile",
          text:
            typeof bar.theme?.fg === "function"
              ? bar.theme.fg("accent", activeProfile)
              : activeProfile,
        }
      : null;
  const parts = profilePart
    ? [profilePart, ...bar.parts.filter((part) => part.key !== "profile")]
    : bar.parts;

  if (bar.width <= 0 || parts.length === 0) return [""];

  const ordered = parts
    .map((part, index) => ({ ...part, index }))
    .sort(
      (a, b) => (priority.get(a.key) ?? 999) - (priority.get(b.key) ?? 999) || a.index - b.index,
    );

  const separatorContent = bar.separator.trim();
  const separator = separatorContent ? ` ${separatorContent} ` : " ";
  const selected = [];
  let used = 0;
  const separatorWidth = visibleWidth(separator);

  for (const part of ordered) {
    const separatorCost = selected.length > 0 ? separatorWidth : 0;
    const available = bar.width - used - separatorCost;
    const text = part.key === "cwd" ? fitCwd(part.text, available) : part.text;
    if (text === null || visibleWidth(text) > available) break;
    selected.push(text);
    used += separatorCost + visibleWidth(text);
  }

  if (selected.length > 0) return [selected.join(separator)];
  if (ordered[0].key === "cwd") return [""];
  return [truncateAnsi(ordered[0].text, bar.width)];
}
