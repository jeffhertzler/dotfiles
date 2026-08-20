import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import feedbackExtension, {
  collectAssistantCaptures,
  type AssistantCapture,
} from "../dot_pi/agent/extensions/feedback.ts";

function assistant(id: string, parentId: string | null, text: string): any {
  return {
    type: "message",
    id,
    parentId,
    timestamp: "2026-08-18T12:00:00.000Z",
    message: {
      role: "assistant",
      content: [{ type: "text", text }],
      provider: "test",
      model: "test",
      usage: {},
      stopReason: "stop",
      timestamp: 1,
    },
  };
}

function user(id: string, parentId: string | null, text: string): any {
  return {
    type: "message",
    id,
    parentId,
    timestamp: "2026-08-18T12:00:00.000Z",
    message: { role: "user", content: text, timestamp: 1 },
  };
}

test("assistant captures include selectable responses from the full session tree", () => {
  const entries = [
    user("u1", null, "start"),
    assistant("a1", "u1", "First answer"),
    user("u2", "a1", "active branch"),
    assistant("a2", "u2", "Second answer"),
    user("u3", "a1", "alternate branch"),
    assistant("a3", "u3", "Alternate answer"),
  ];

  assert.deepEqual(collectAssistantCaptures(entries), [
    { entryId: "a1", markdown: "First answer" },
    { entryId: "a2", markdown: "Second answer" },
    { entryId: "a3", markdown: "Alternate answer" },
  ] satisfies AssistantCapture[]);
});

test("feedback can select an older assistant response before opening Neovim", async () => {
  const root = mkdtempSync(join(tmpdir(), "pi-feedback-test-"));
  const previousNvim = process.env.PI_FEEDBACK_NVIM;
  process.env.PI_FEEDBACK_NVIM = "/bin/true";
  try {
    const entries = [
      user("u1", null, "start"),
      assistant("a1", "u1", "Older response to annotate"),
      user("u2", "a1", "continue"),
      assistant("a2", "u2", "Latest response"),
    ];
    let registered: any;
    const attentionEvents: Array<{ name: string; data: unknown }> = [];
    const pi = {
      registerCommand(name: string, options: any) {
        assert.equal(name, "feedback");
        registered = options;
      },
      setLabel() {},
      events: {
        emit(name: string, data: unknown) {
          attentionEvents.push({ name, data });
        },
      },
    };
    const notifications: string[] = [];
    let customCalls = 0;
    let selectCalls = 0;
    const ctx: any = {
      mode: "tui",
      waitForIdle: async () => {},
      sessionManager: {
        getSessionId: () => "session-1",
        getSessionDir: () => root,
        getSessionFile: () => join(root, "session.jsonl"),
        getEntries: () => entries,
        getBranch: () => entries,
        getTree: () => [],
        getLeafId: () => "a2",
      },
      ui: {
        notify(message: string) {
          notifications.push(message);
        },
        async select(title: string, choices: string[]) {
          selectCalls += 1;
          assert.equal(title, "Choose assistant response from the session tree");
          assert.match(choices[0], /^Latest response · Latest response \[a2\]$/);
          assert.match(choices[1], /^1 response back · Older response to annotate \[a1\]$/);
          return choices[1];
        },
        async custom(factory: any) {
          customCalls += 1;
          let result: unknown;
          factory(
            { stop() {}, start() {}, requestRender() {}, terminal: { rows: 40 } },
            {},
            {},
            (value: unknown) => { result = value; },
          );
          return result;
        },
      },
    };

    feedbackExtension(pi as any);
    await registered.handler("", ctx);

    assert.equal(selectCalls, 1, "message picker should run before the Neovim UI");
    assert.equal(customCalls, 1, "Neovim should open after selecting a response");
    const sourcePath = join(root, "feedback", "session-1", "a1", "source.md");
    assert.equal(readFileSync(sourcePath, "utf8"), "Older response to annotate\n");
    assert.equal(notifications.at(-1), "Feedback discarded");
    assert.deepEqual(attentionEvents, [
      { name: "human-attention:notifications-suppressed", data: { active: true } },
      { name: "human-attention:notifications-suppressed", data: { active: false } },
      { name: "human-attention:notifications-suppressed", data: { active: true } },
      { name: "human-attention:notifications-suppressed", data: { active: false } },
    ]);
  } finally {
    if (previousNvim === undefined) delete process.env.PI_FEEDBACK_NVIM;
    else process.env.PI_FEEDBACK_NVIM = previousNvim;
    rmSync(root, { recursive: true, force: true });
  }
});
