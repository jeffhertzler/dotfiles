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

for (const scenario of ["clean", "local work", "diverged target", "dirty", "wrong branch"] as const) {
	test(`explicit branch migration: ${scenario}`, (t) => {
		const root = mkdtempSync(join(tmpdir(), "herdr-plugin-migrate-"));
		t.after(() => rmSync(root, { recursive: true, force: true }));
		const { origin, seed, upstream } = createRemotePair(root);
		const oldRef = "agent/windows-support";
		git(seed, "switch", "-c", oldRef);
		writeFileSync(join(seed, "windows.txt"), "windows behavior\n");
		git(seed, "add", "windows.txt");
		git(seed, "commit", "-m", "Windows behavior");
		git(seed, "push", "origin", oldRef);
		git(seed, "switch", "main");
		git(seed, "merge", "--no-ff", "-m", "Unify platforms", oldRef);
		git(seed, "push", "origin", "main");
		const checkout = join(root, "checkout");
		run("git", ["clone", "--single-branch", "--branch", oldRef, origin, checkout]);
		git(checkout, "config", "user.email", "test@example.com");
		git(checkout, "config", "user.name", "Test User");
		if (scenario === "diverged target") git(checkout, "switch", "-c", "main");
		if (scenario === "wrong branch") git(checkout, "switch", "-c", "unrelated");
		if (scenario === "local work" || scenario === "diverged target" || scenario === "dirty") {
			writeFileSync(join(checkout, "personal.txt"), "must survive\n");
			if (scenario !== "dirty") {
				git(checkout, "add", "personal.txt");
				git(checkout, "commit", "-m", "Personal work");
			}
		}
		if (scenario === "diverged target") git(checkout, "switch", oldRef);
		const before = git(checkout, "rev-parse", "HEAD");
		const beforeBranch = git(checkout, "branch", "--show-current");
		const fake = createFakeHerdr(root);
		const args = [reconciler, "--id", "worktrunk", "--path", checkout,
			"--origin-url", origin, "--upstream-url", upstream, "--ref", "main", "--previous-ref", oldRef];
		const env = { ...process.env, HERDR_TEST_LOG: fake.log, PATH: `${fake.bin}:${process.env.PATH}` };
		const result = spawnSync(process.execPath, args, { encoding: "utf8", env });
		if (scenario === "clean") {
			assert.equal(result.status, 0, result.stderr);
			assert.equal(git(checkout, "branch", "--show-current"), "main");
			assert.equal(git(checkout, "rev-parse", "HEAD"), git(seed, "rev-parse", "main"));
			assert.equal(git(checkout, "rev-parse", "@{upstream}"), git(seed, "rev-parse", "main"));
			assert.equal(readFileSync(join(checkout, "windows.txt"), "utf8"), "windows behavior\n");
			run(process.execPath, args, undefined, env); // idempotent after switching
		} else {
			assert.notEqual(result.status, 0);
			assert.equal(git(checkout, "rev-parse", "HEAD"), before);
			assert.equal(git(checkout, "branch", "--show-current"), beforeBranch);
			if (scenario === "dirty" || scenario === "local work") {
				assert.equal(readFileSync(join(checkout, "personal.txt"), "utf8"), "must survive\n");
			}
		}
	});
}

test("Worktrunk templates use unified main and platform-specific native action IDs", () => {
	const data = readFileSync(join(sourceRoot, ".chezmoidata/herdr.yaml"), "utf8");
	const worktrunk = data.split("  - id: worktrunk\n")[1].split("  - id:")[0];
	assert.match(worktrunk, /managedRef: main/);
	assert.match(worktrunk, /windowsRef: main/);
	assert.match(worktrunk, /windowsPreviousRef: agent\/windows-support/);
	for (const os of ["windows", "linux", "darwin"]) {
		const rendered = run("chezmoi", ["execute-template", "--source", sourceRoot,
			"--override-data", JSON.stringify({ chezmoi: { os, homeDir: "C:/Users/Test User" } }),
			"--file", join(sourceRoot, "dot_config/herdr/config.toml.tmpl")]);
		for (const action of ["open", "new-current", "remove-current"]) {
			assert.ok(rendered.includes(`command = "worktrunk.${action}${os === "windows" ? "-windows" : ""}"`));
		}
		if (os === "windows") assert.match(rendered, /default_shell = "C:\/Program Files\/Git\/bin\/bash.exe"/);
	}
});
