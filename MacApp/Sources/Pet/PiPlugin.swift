//  PiPlugin.swift
//  Desktop Pet
//
//  The TypeScript extension written into pi's extensions folder.

import Cocoa

enum PiPlugin {
    static var source: String {
        """
        // Desktop Pet — pi extension.
        //
        // Written by `pet plugin install pi`. Reports what pi is doing to the
        // pet by writing one line to its state file:
        //     EVENT|TOOL|EPOCH
        // Remove it with `pet plugin uninstall pi`. Needs pi 0.83 or later.

        import { writeFileSync, mkdirSync } from "node:fs"
        import { homedir } from "node:os"
        import { join } from "node:path"

        const dir = process.env.PET_CONFIG_DIR || join(homedir(), ".config", "pet")

        function record(event, tool = "") {
          try {
            mkdirSync(dir, { recursive: true })
            writeFileSync(join(dir, "state"),
                          `${event}|${tool}|${Math.floor(Date.now() / 1000)}\\n`)
          } catch (e) {
            // never let the pet interfere with a session
          }
        }

        export default function (pi) {
          pi.on("session_start", async () => record("SessionStart"))
          pi.on("input", async () => record("UserPromptSubmit"))
          pi.on("tool_execution_start", async (ev) =>
            record("PreToolUse", ev?.toolName ?? ""))
          pi.on("tool_execution_end", async (ev) =>
            // a failed tool shows the Failed pose instead of Review
            record(ev?.isError ? "PostToolUseFailure" : "PostToolUse",
                   ev?.toolName ?? ""))
          pi.on("ui_prompt_start", async () => record("Notification"))
          pi.on("agent_end", async () => record("Stop"))
          pi.on("session_shutdown", async () => record("SessionEnd"))
        }
        """
    }
}
