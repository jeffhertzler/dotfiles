#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

function fail(message) {
	console.error(`herdr-plugin-reconcile: ${message}`);
	process.exit(1);
}

function parseArgs(argv) {
	const options = {};
	for (let index = 0; index < argv.length; index += 2) {
		const flag = argv[index];
		const value = argv[index + 1];
		if (!flag?.startsWith("--") || value === undefined) fail(`invalid argument: ${flag ?? ""}`);
		options[flag.slice(2)] = value;
	}
	for (const key of ["id", "path", "origin-url", "upstream-url", "ref"]) {
		if (!options[key]) fail(`missing --${key}`);
	}
	return {
		id: options.id,
		path: resolve(options.path),
		originUrl: options["origin-url"],
		upstreamUrl: options["upstream-url"],
		ref: options.ref,
	};
}

function commandResult(command, args, options = {}) {
	const result = spawnSync(command, args, {
		cwd: options.cwd,
		encoding: "utf8",
		stdio: options.capture ? "pipe" : "inherit",
	});
	if (result.error) fail(`${command} could not start: ${result.error.message}`);
	return result;
}

function run(command, args, options = {}) {
	const result = commandResult(command, args, options);
	if (result.status !== 0) {
		const detail = options.capture ? (result.stderr || result.stdout).trim() : "";
		fail(`${command} ${args.join(" ")} failed${detail ? `: ${detail}` : ""}`);
	}
	return options.capture ? result.stdout.trim() : "";
}

const options = parseArgs(process.argv.slice(2));
const manifest = join(options.path, "herdr-plugin.toml");

if (!existsSync(manifest)) {
	mkdirSync(dirname(options.path), { recursive: true });
	run("git", [
		"clone",
		"--branch",
		options.ref,
		"--single-branch",
		options.originUrl,
		options.path,
	]);
}

run("git", ["rev-parse", "--is-inside-work-tree"], { cwd: options.path, capture: true });
const changes = run("git", ["status", "--porcelain"], { cwd: options.path, capture: true });
if (changes) fail(`plugin checkout has uncommitted changes: ${options.path}`);

const branch = run("git", ["branch", "--show-current"], { cwd: options.path, capture: true });
if (branch !== options.ref) fail(`plugin checkout is on ${branch || "a detached HEAD"}, expected ${options.ref}`);

const origin = run("git", ["remote", "get-url", "origin"], {
	cwd: options.path,
	capture: true,
});
if (origin !== options.originUrl) fail(`unexpected origin ${origin}; expected ${options.originUrl}`);

const upstreamResult = commandResult("git", ["remote", "get-url", "upstream"], {
	cwd: options.path,
	capture: true,
});
if (upstreamResult.status !== 0) {
	run("git", ["remote", "add", "upstream", options.upstreamUrl], { cwd: options.path });
} else if (upstreamResult.stdout.trim() !== options.upstreamUrl) {
	fail(`unexpected upstream ${upstreamResult.stdout.trim()}; expected ${options.upstreamUrl}`);
}

console.log(`Updating Herdr plugin ${options.id} from origin/${options.ref}`);
run("git", ["fetch", "origin", options.ref], { cwd: options.path });
run("git", ["merge", "--ff-only", `origin/${options.ref}`], { cwd: options.path });
const head = run("git", ["rev-parse", "HEAD"], { cwd: options.path, capture: true });
const originHead = run("git", ["rev-parse", `origin/${options.ref}`], {
	cwd: options.path,
	capture: true,
});
if (head !== originHead) fail(`local ${options.ref} does not match origin/${options.ref}`);

run("git", ["fetch", "upstream", "main"], { cwd: options.path });

console.log(`Linking Herdr plugin ${options.id} from ${options.path}`);
run("herdr", ["plugin", "link", options.path]);
