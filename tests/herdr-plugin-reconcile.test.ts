import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const sourceRoot = fileURLToPath(new URL("..", import.meta.url));
const reconciler = join(
	sourceRoot,
	"dot_local",
	"bin",
	"executable_herdr-plugin-reconcile.mjs",
);

function run(command: string, args: string[], cwd?: string, env?: NodeJS.ProcessEnv) {
	const result = spawnSync(command, args, {
		cwd,
		encoding: "utf8",
		env: { ...process.env, ...env },
	});
	assert.equal(result.status, 0, result.stderr || result.stdout);
	return result.stdout;
}

function git(cwd: string, ...args: string[]) {
	return run("git", args, cwd).trim();
}

function createRemotePair(root: string) {
	const seed = join(root, "seed");
	const origin = join(root, "origin.git");
	const upstream = join(root, "upstream.git");
	mkdirSync(seed, { recursive: true });
	run("git", ["init", "--initial-branch=main", seed]);
	git(seed, "config", "user.email", "test@example.com");
	git(seed, "config", "user.name", "Test User");
	writeFileSync(join(seed, "herdr-plugin.toml"), 'id = "worktrunk"\n');
	git(seed, "add", "herdr-plugin.toml");
	git(seed, "commit", "-m", "initial plugin");
	run("git", ["init", "--bare", origin]);
	run("git", ["init", "--bare", upstream]);
	git(seed, "remote", "add", "origin", origin);
	git(seed, "remote", "add", "upstream", upstream);
	git(seed, "push", "origin", "main");
	git(seed, "push", "upstream", "main");
	return { origin, seed, upstream };
}

function createFakeHerdr(root: string) {
	const bin = join(root, "bin");
	const log = join(root, "herdr.log");
	mkdirSync(bin, { recursive: true });
	const executable = join(bin, "herdr");
	writeFileSync(
		executable,
		`#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "$HERDR_TEST_LOG"\nif [[ $1 == plugin && $2 == list ]]; then\n  printf '{"result":{"plugins":[{"plugin_id":"worktrunk","enabled":true}]}}\\n'\nfi\n`,
		{ mode: 0o755 },
	);
	return { bin, log };
}

test("clones the selected fork branch, records public upstream, and links it", (t) => {
	const root = mkdtempSync(join(tmpdir(), "herdr-plugin-reconcile-test-"));
	t.after(() => rmSync(root, { recursive: true, force: true }));
	const { origin, upstream } = createRemotePair(root);
	const checkout = join(root, "checkout");
	const fake = createFakeHerdr(root);

	run(
		process.execPath,
		[
			reconciler,
			"--id",
			"worktrunk",
			"--path",
			checkout,
			"--origin-url",
			origin,
			"--upstream-url",
			upstream,
			"--ref",
			"main",
		],
		undefined,
		{
			HERDR_TEST_LOG: fake.log,
			PATH: `${fake.bin}:${process.env.PATH}`,
		},
	);

	assert.equal(git(checkout, "branch", "--show-current"), "main");
	assert.equal(git(checkout, "remote", "get-url", "origin"), origin);
	assert.equal(git(checkout, "remote", "get-url", "upstream"), upstream);
	assert.match(readFileSync(fake.log, "utf8"), /plugin link .*checkout/);
	assert.equal(dirname(git(checkout, "rev-parse", "--git-dir")), ".");
});

test("fast-forwards only from origin and refuses a dirty checkout", (t) => {
	const root = mkdtempSync(join(tmpdir(), "herdr-plugin-reconcile-update-test-"));
	t.after(() => rmSync(root, { recursive: true, force: true }));
	const { origin, seed, upstream } = createRemotePair(root);
	const checkout = join(root, "checkout");
	const fake = createFakeHerdr(root);
	const args = [
		reconciler,
		"--id",
		"worktrunk",
		"--path",
		checkout,
		"--origin-url",
		origin,
		"--upstream-url",
		upstream,
		"--ref",
		"main",
	];
	const env = {
		...process.env,
		HERDR_TEST_LOG: fake.log,
		PATH: `${fake.bin}:${process.env.PATH}`,
	};

	run(process.execPath, args, undefined, env);
	writeFileSync(join(seed, "version.txt"), "origin update\n");
	git(seed, "add", "version.txt");
	git(seed, "commit", "-m", "origin update");
	git(seed, "push", "origin", "main");
	const expectedHead = git(seed, "rev-parse", "HEAD");

	run(process.execPath, args, undefined, env);
	assert.equal(git(checkout, "rev-parse", "HEAD"), expectedHead);

	writeFileSync(join(checkout, "dirty.txt"), "do not overwrite\n");
	const dirtyRun = spawnSync(process.execPath, args, { encoding: "utf8", env });
	assert.notEqual(dirtyRun.status, 0);
	assert.match(dirtyRun.stderr, /uncommitted changes/);
	assert.equal(readFileSync(join(checkout, "dirty.txt"), "utf8"), "do not overwrite\n");

	rmSync(join(checkout, "dirty.txt"));
	git(checkout, "config", "user.email", "test@example.com");
	git(checkout, "config", "user.name", "Test User");
	writeFileSync(join(checkout, "local-only.txt"), "not pushed\n");
	git(checkout, "add", "local-only.txt");
	git(checkout, "commit", "-m", "local-only change");
	const aheadRun = spawnSync(process.execPath, args, { encoding: "utf8", env });
	assert.notEqual(aheadRun.status, 0);
	assert.match(aheadRun.stderr, /does not match origin\/main/);
});
