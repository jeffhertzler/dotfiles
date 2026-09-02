import assert from "node:assert/strict";
import test from "node:test";
import { setDefaultMcpUiViewer } from "../dot_pi/agent/extensions/mcp-ui-viewer.ts";

test("defaults MCP UI viewer to none", () => {
  const env: NodeJS.ProcessEnv = {};

  setDefaultMcpUiViewer(env);

  assert.equal(env.MCP_UI_VIEWER, "none");
});

test("preserves an explicit MCP UI viewer override", () => {
  const env: NodeJS.ProcessEnv = { MCP_UI_VIEWER: "browser" };

  setDefaultMcpUiViewer(env);

  assert.equal(env.MCP_UI_VIEWER, "browser");
});
