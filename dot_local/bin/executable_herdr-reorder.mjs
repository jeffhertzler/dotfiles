#!/usr/bin/env node

import fs from 'node:fs';
import { createHash } from 'node:crypto';
import net from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [kind, direction] = process.argv.slice(2);
const socketPath = process.env.HERDR_SOCKET_PATH;
const socketEndpoint =
  process.platform === 'win32' && socketPath ? `\\\\.\\pipe\\${socketPath}` : socketPath;
const workspaceId = process.env.HERDR_ACTIVE_WORKSPACE_ID || process.env.HERDR_WORKSPACE_ID;
const tabId = process.env.HERDR_ACTIVE_TAB_ID || process.env.HERDR_TAB_ID;
let requestId = 0;

function usage() {
  throw new Error('usage: herdr-reorder.mjs tab left|right | workspace up|down');
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function acquireLock() {
  if (!socketPath) throw new Error('HERDR_SOCKET_PATH is unavailable');
  const lockDirectory = join(process.env.XDG_RUNTIME_DIR || tmpdir(), 'herdr-reorder');
  fs.mkdirSync(lockDirectory, { recursive: true, mode: 0o700 });
  const socketKey = createHash('sha256').update(socketPath).digest('hex').slice(0, 16);
  const lockPath = join(lockDirectory, `${socketKey}.lock`);

  for (let attempt = 0; attempt < 150; attempt += 1) {
    try {
      const handle = fs.openSync(lockPath, 'wx');
      return () => {
        fs.closeSync(handle);
        try {
          fs.unlinkSync(lockPath);
        } catch (error) {
          if (error.code !== 'ENOENT') throw error;
        }
      };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      try {
        const age = Date.now() - fs.statSync(lockPath).mtimeMs;
        if (age > 10000) fs.unlinkSync(lockPath);
      } catch (statError) {
        if (statError.code !== 'ENOENT') throw statError;
      }
      await sleep(20);
    }
  }

  throw new Error('timed out waiting for another reorder command');
}

function socket(method, params = {}) {
  if (!socketPath) throw new Error('HERDR_SOCKET_PATH is unavailable');

  return new Promise((resolve, reject) => {
    const client = net.connect(socketEndpoint);
    let buffer = '';
    const timer = setTimeout(() => {
      client.destroy();
      reject(new Error(`${method} timed out`));
    }, 3000);

    const finish = (callback, value) => {
      clearTimeout(timer);
      client.end();
      callback(value);
    };

    client.on('connect', () => {
      client.write(`${JSON.stringify({ id: `herdr-reorder:${++requestId}`, method, params })}\n`);
    });
    client.on('data', (data) => {
      buffer += data;
      const newline = buffer.indexOf('\n');
      if (newline < 0) return;

      let message;
      try {
        message = JSON.parse(buffer.slice(0, newline));
      } catch (error) {
        finish(reject, new Error(`${method} returned invalid JSON: ${error.message}`));
        return;
      }

      if (message.error) {
        finish(reject, new Error(message.error.message || `${method} failed`));
      } else {
        finish(resolve, message.result);
      }
    });
    client.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

async function notifyError(error) {
  const body = error instanceof Error ? error.message : String(error);
  try {
    await socket('notification.show', {
      title: 'Reorder failed',
      body,
      sound: 'none',
    });
  } catch {
    // The original socket error is more useful than a secondary notification error.
  }
  console.error(`herdr-reorder: ${body}`);
}

async function reorderTab() {
  if (!['left', 'right'].includes(direction) || kind !== 'tab') usage();
  if (!workspaceId || !tabId) throw new Error('active Herdr tab is unavailable');

  const result = await socket('tab.list', { workspace_id: workspaceId });
  const tabs = result?.tabs || [];
  const index = tabs.findIndex((tab) => tab.tab_id === tabId);
  if (index < 0) throw new Error(`active tab ${tabId} was not found`);

  if (direction === 'left') {
    if (index === 0) return;
    await socket('tab.move', { tab_id: tabId, insert_index: index - 1 });
    return;
  }

  if (index === tabs.length - 1) return;
  await socket('tab.move', { tab_id: tabId, insert_index: index + 2 });
}

function worktreeKey(workspace) {
  return workspace.worktree?.repo_key || workspace.worktree?.repo_root || null;
}

function workspaceUnits(workspaces) {
  const grouped = new Map();
  for (const workspace of workspaces) {
    const key = worktreeKey(workspace);
    if (!key) continue;
    const group = grouped.get(key) || [];
    group.push(workspace);
    grouped.set(key, group);
  }

  const qualifying = new Set(
    [...grouped.entries()]
      .filter(([, members]) => members.length > 1 && members.some((workspace) => workspace.worktree?.is_linked_worktree === false))
      .map(([key]) => key)
  );
  const emitted = new Set();
  const units = [];

  for (const workspace of workspaces) {
    const key = worktreeKey(workspace);
    if (!key || !qualifying.has(key)) {
      units.push([workspace]);
      continue;
    }
    if (emitted.has(key)) continue;
    emitted.add(key);
    units.push(grouped.get(key));
  }

  for (const unit of units) {
    if (unit.length < 2) continue;
    const positions = unit.map((workspace) => workspaces.findIndex((candidate) => candidate.workspace_id === workspace.workspace_id));
    if (!positions.every((position, index) => index === 0 || position === positions[index - 1] + 1)) {
      throw new Error('worktree group members are not contiguous; refusing to reorder unrelated workspaces');
    }
  }

  return units;
}

async function reorderWorkspace() {
  if (!['up', 'down'].includes(direction) || kind !== 'workspace') usage();
  if (!workspaceId) throw new Error('active Herdr workspace is unavailable');

  const result = await socket('workspace.list');
  const workspaces = result?.workspaces || [];
  const units = workspaceUnits(workspaces);
  const unitIndex = units.findIndex((unit) => unit.some((workspace) => workspace.workspace_id === workspaceId));
  if (unitIndex < 0) throw new Error(`active workspace ${workspaceId} was not found`);

  const targetIndex = direction === 'up' ? unitIndex - 1 : unitIndex + 1;
  if (targetIndex < 0 || targetIndex >= units.length) return;

  const movingUnit = units[unitIndex];
  const beforeUnit = direction === 'up' ? units[targetIndex] : units[targetIndex + 1];
  const params = {
    workspace_ids: movingUnit.map((workspace) => workspace.workspace_id),
  };
  if (beforeUnit) params.before_workspace_id = beforeUnit[0].workspace_id;

  const moved = await socket('workspace.move_block', params);
  const expected = [...units];
  [expected[unitIndex], expected[targetIndex]] = [expected[targetIndex], expected[unitIndex]];
  const expectedIds = expected.flat().map((workspace) => workspace.workspace_id);
  const actualIds = (moved?.workspaces || []).map((workspace) => workspace.workspace_id);
  if (actualIds.join('\0') !== expectedIds.join('\0')) {
    throw new Error('Herdr returned an unexpected workspace order');
  }
}

let releaseLock;
let failure;
try {
  releaseLock = await acquireLock();
  if (kind === 'tab') {
    await reorderTab();
  } else if (kind === 'workspace') {
    await reorderWorkspace();
  } else {
    usage();
  }
} catch (error) {
  failure = error;
} finally {
  if (releaseLock) releaseLock();
}

if (failure) {
  await notifyError(failure);
  process.exitCode = 1;
}
