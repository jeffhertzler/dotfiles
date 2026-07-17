#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const bin = process.env.HERDR_BIN_PATH || 'herdr';
const pane = process.env.HERDR_ACTIVE_PANE_ID || process.env.HERDR_PANE_ID;
const cwd = process.env.HERDR_ACTIVE_PANE_CWD || process.cwd();
const [mode, direction] = process.argv.slice(2);

if (!pane || !['local', 'full'].includes(mode) || !['left', 'down', 'up', 'right'].includes(direction)) {
  console.error('usage: herdr-directional-split.mjs <local|full> <left|down|up|right>');
  process.exit(2);
}

function herdr(...args) {
  const output = execFileSync(bin, args, { encoding: 'utf8' }).trim();
  return output ? JSON.parse(output) : null;
}

function createdPaneId(result) {
  const id = result?.result?.pane?.pane_id;
  if (!id) throw new Error('Herdr did not return the new pane id');
  return id;
}

function localSplit(dir) {
  const nativeDirection = dir === 'left' || dir === 'right' ? 'right' : 'down';
  const before = dir === 'left' || dir === 'up';
  const result = herdr(
    'pane',
    'split',
    pane,
    '--direction',
    nativeDirection,
    '--cwd',
    cwd,
    before ? '--no-focus' : '--focus',
  );
  const newPane = createdPaneId(result);

  if (before) {
    try {
      // Herdr only creates right/down. Swapping with the new pane as the source
      // places it left/up and focuses it, matching tmux split-window -b.
      herdr('pane', 'swap', '--source-pane', newPane, '--target-pane', pane);
    } catch (error) {
      try {
        herdr('pane', 'close', newPane);
      } catch {}
      throw error;
    }
  }

  return newPane;
}

async function layoutTools() {
  const result = herdr('plugin', 'list', '--plugin', 'edi.layout-tools', '--json');
  const plugin = result?.result?.plugins?.[0];
  if (!plugin?.plugin_root) {
    throw new Error('edi.layout-tools is not installed; run: herdr plugin install edouard-andrei/herdr-layout-tools');
  }
  return import(pathToFileURL(join(plugin.plugin_root, 'herdr.mjs')).href);
}

async function fullSplit(dir) {
  const tools = await layoutTools();
  const exported = await tools.socket('layout.export', { pane_id: pane });
  const oldRoot = exported?.layout?.root;
  if (!oldRoot) throw new Error('Unable to export the current Herdr layout');

  // With one pane, a leaf split already spans the whole tab.
  if (oldRoot.type === 'pane') return localSplit(dir);

  // The temporary leaf placement is irrelevant: applyTreeInPlace reconstructs
  // the desired root while moving, rather than restarting, every live pane.
  const nativeDirection = dir === 'left' || dir === 'right' ? 'right' : 'down';
  const result = herdr(
    'pane',
    'split',
    pane,
    '--direction',
    nativeDirection,
    '--cwd',
    cwd,
    '--no-focus',
  );
  const newPane = createdPaneId(result);
  const newLeaf = { type: 'pane', pane_id: newPane };
  const before = dir === 'left' || dir === 'up';
  const root = {
    type: 'split',
    direction: nativeDirection,
    ratio: 0.5,
    first: before ? newLeaf : oldRoot,
    second: before ? oldRoot : newLeaf,
  };

  tools.applyTreeInPlace(root);
  // The new full-span pane overlaps every old pane along the shared border, so
  // focusing from the original pane in the requested direction is unambiguous.
  herdr('pane', 'focus', '--direction', dir, '--pane', pane);
  return newPane;
}

try {
  const newPane = mode === 'full' ? await fullSplit(direction) : localSplit(direction);
  console.log(newPane);
} catch (error) {
  console.error(`herdr directional split failed: ${error instanceof Error ? error.message : error}`);
  process.exit(1);
}
