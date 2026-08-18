import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import atuinPiExtension from "../dot_pi/agent/extensions/atuin.ts";

type Handler = (event: any, ctx: any) => unknown;

const managedExtension = new URL("../dot_pi/agent/extensions/atuin.ts", import.meta.url);

function createHarness() {
	const calls: Array<{ command: string; args: string[]; options: unknown }> = [];
	const handlers = new Map<string, Handler[]>();
	const pi = {
		async exec(command: string, args: string[], options: unknown) {
			calls.push({ command, args, options });
			return args[1] === "start"
				? { code: 0, stdout: "history-id\n", stderr: "", killed: false }
				: { code: 0, stdout: "", stderr: "", killed: false };
		},
		on(event: string, handler: Handler) {
			handlers.set(event, [...(handlers.get(event) ?? []), handler]);
		},
	};

	atuinPiExtension(pi as any);
	return { calls, handlers };
}

test("managed extension exactly matches the installed Atuin release", (t) => {
	const home = mkdtempSync(join(tmpdir(), "atuin-pi-extension-test-"));
	t.after(() => rmSync(home, { recursive: true, force: true }));

	const result = spawnSync("atuin", ["hook", "install", "pi"], {
		encoding: "utf8",
		env: { ...process.env, HOME: home, USERPROFILE: home },
	});
	assert.equal(result.status, 0, result.stderr || result.stdout);

	const generated = readFileSync(join(home, ".pi", "agent", "extensions", "atuin.ts"), "utf8");
	assert.equal(
		readFileSync(managedExtension, "utf8"),
		generated,
		"Atuin's bundled pi extension changed; regenerate the managed snapshot and review the diff",
	);
});

test("records a pi bash command with its cwd and exit code", async () => {
	const { calls, handlers } = createHarness();
	const context = { cwd: "/repo/worktree" };

	await handlers.get("tool_call")?.[0]?.(
		{
			toolName: "bash",
			toolCallId: "call-1",
			input: { command: "npm test" },
		},
		context,
	);
	await handlers.get("tool_execution_end")?.[0]?.(
		{
			toolCallId: "call-1",
			isError: true,
			result: { content: [{ type: "text", text: "Command exited with code 7" }] },
		},
		context,
	);

	assert.deepEqual(calls, [
		{
			command: "atuin",
			args: ["history", "start", "--author", "pi", "--", "npm test"],
			options: { cwd: "/repo/worktree", timeout: 10_000 },
		},
		{
			command: "atuin",
			args: ["history", "end", "history-id", "--exit", "7"],
			options: { cwd: "/repo/worktree", timeout: 10_000 },
		},
	]);
});

test("ignores non-bash tools", async () => {
	const { calls, handlers } = createHarness();

	await handlers.get("tool_call")?.[0]?.(
		{
			toolName: "read",
			toolCallId: "call-2",
			input: { path: "README.md" },
		},
		{ cwd: "/repo" },
	);

	assert.deepEqual(calls, []);
});
