//  OpencodePlugin.swift
//  Desktop Pet
//
//  The JavaScript plugin written into opencode's plugin folder.

import Cocoa

enum OpencodePlugin {
    static var source: String {
        """
        // Desktop Pet — opencode plugin.
        //
        // Written by `pet plugin install opencode`. Reports what opencode is
        // doing to the pet by writing one line to its state file:
        //     EVENT|TOOL|EPOCH
        // Remove it with `pet plugin uninstall opencode`.

        import { writeFileSync, mkdirSync } from "fs"
        import { homedir } from "os"
        import { join } from "path"

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

        // opencode passes (input, output); the tool name has moved around
        // between versions, so try the shapes it has used.
        function toolName(input) {
          return input?.tool ?? input?.name ?? input?.toolName ?? ""
        }

        export const DesktopPet = async () => ({
          "session.created":     async () => record("SessionStart"),
          "session.idle":        async () => record("Stop"),
          "session.error":       async () => record("StopFailure"),
          "permission.asked":    async () => record("Notification"),
          "tool.execute.before": async (input) => record("PreToolUse", toolName(input)),
          "tool.execute.after":  async (input, output) => {
            // a failed tool shows the Failed pose instead of Review
            const failed = output?.error ?? output?.result?.error ?? output?.isError
            record(failed ? "PostToolUseFailure" : "PostToolUse", toolName(input))
          },
        })
        """
    }
}
