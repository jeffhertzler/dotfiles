import { writeSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

interface ExitTerminal {
  termProgram: string | undefined;
  isTTY: boolean;
  onExit: (callback: () => void) => void;
  write: (sequence: string) => void;
}

/** Leave no visible Kitty images over the shell after an interactive Pi quits. */
export default function herdrImageCleanup(pi: ExtensionAPI, terminal: ExitTerminal = {
  termProgram: process.env.TERM_PROGRAM,
  isTTY: process.stdout.isTTY === true,
  onExit: (callback) => { process.once("exit", callback); },
  write: (sequence) => { writeSync(process.stdout.fd, sequence); },
}) {
  let scheduled = false;
  pi.on("session_shutdown", (event, ctx) => {
    if (event.reason !== "quit" || ctx.mode !== "tui" || terminal.termProgram !== "herdr" || !terminal.isTTY || scheduled) return;
    scheduled = true;
    // Regular-mode stop preserves images; other exit paths can restore/repaint
    // screens after session_shutdown. Clean the final screen at process exit,
    // not during reload/session replacement or before terminal restoration.
    terminal.onExit(() => {
      try {
        // Kitty delete-visible-all: graphics only, not text or scrollback.
        // Synchronous output is required inside Node's exit event.
        terminal.write("\x1b_Ga=d,d=A,q=2;\x1b\\");
      } catch {
        // A detached/dead terminal must not prevent Pi from exiting.
      }
    });
  });
}
