import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export function setDefaultMcpUiViewer(env: NodeJS.ProcessEnv = process.env): void {
  env.MCP_UI_VIEWER ??= "none";
}

export default function mcpUiViewer(_pi: ExtensionAPI): void {
  setDefaultMcpUiViewer();
}
