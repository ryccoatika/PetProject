//  CLI+Usage.swift
//  Desktop Pet
//
//  `pet statusline` — installed into Claude Code's statusLine setting so the
//  app can read the rate-limit numbers hooks never receive. `pet usage` is
//  the human-facing readout of the same file.

import Cocoa

extension CLI {

    /// Called by Claude Code with the statusline JSON on stdin. Records the
    /// rate-limit numbers, chains to whatever statusline was there before
    /// (see HookPlugin.mergeStatusLine), and prints its output plus ours.
    /// Always exits 0: a status line that fails just goes blank, never
    /// blocks the UI.
    static func statusline(_ args: [String]) -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let rateLimits = json["rate_limits"] as? [String: Any] {
            UsageStore.write(rateLimits: rateLimits)
        }

        var claudeDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        if let i = args.firstIndex(of: "--claude-dir"), i + 1 < args.count {
            claudeDir = URL(fileURLWithPath: args[i + 1])
        }

        if let previous = HookPlugin.previousStatusLineCommand(claudeDir: claudeDir) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", previous]
            let stdin = Pipe(), stdout = Pipe()
            proc.standardInput = stdin
            proc.standardOutput = stdout
            do {
                try proc.run()
                stdin.fileHandleForWriting.write(data)
                stdin.fileHandleForWriting.closeFile()
                proc.waitUntilExit()
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: out, encoding: .utf8), !text.isEmpty {
                    print(text.trimmingCharacters(in: .newlines))
                }
            } catch {
                Log.error("statusline: could not run the previous command: \(previous)")
            }
        }
        exit(0)
    }

    /// `pet usage` — the numbers /usage shows, read from the file `pet
    /// statusline` keeps updated.
    static func usage(_ action: String?) {
        Prefs.refresh()
        switch action {
        case "show", "hide":
            Prefs.store.set(action == "hide", forKey: "petUsageHidden")
            Prefs.store.synchronize()
            Prefs.notifyRunningApp()
            print(action == "hide" ? "usage badge hidden" : "usage badge shown")
        case nil, "status":
            guard let snap = UsageStore.read() else {
                print("no usage data yet — needs a Claude Code Pro or Max session")
                return
            }
            if snap.age > UsageStore.staleAfter {
                print("last seen \(Int(snap.age / 60))m ago (stale):")
            }
            if let pct = snap.sessionPercent {
                let reset = UsageStore.humanReset(snap.sessionResetsAt).map { " (resets in \($0))" }
                print("session : \(Int(pct))%\(reset ?? "")")
            }
            if let pct = snap.weekPercent {
                let reset = UsageStore.humanReset(snap.weekResetsAt).map { " (resets in \($0))" }
                print("week    : \(Int(pct))% — all Claude models\(reset ?? "")")
            }
        default:
            fail("usage: pet usage [show | hide]")
        }
    }
}
