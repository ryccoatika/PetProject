//  CLI.swift
//  Desktop Pet
//
//  The `pet` command: dispatch, help, and the hook event entry point.

import Cocoa

enum CLI {
    static func tilde(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(("pet: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }

    /// The bundle this binary belongs to (the CLI is usually a symlink into it).
    static var appURL: URL? {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let macos = exe.deletingLastPathComponent()
        if macos.lastPathComponent == "MacOS" {
            let app = macos.deletingLastPathComponent().deletingLastPathComponent()
            if app.pathExtension == "app" { return app }
        }
        for path in ["\(NSHomeDirectory())/Applications/Pet.app", "/Applications/Pet.app"] {
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Absolute path Claude should call: the installed `pet`, else this binary.
    static var installedCommandPath: String {
        for dir in ["/usr/local/bin", "\(NSHomeDirectory())/.local/bin"] {
            let link = dir + "/pet"
            if FileManager.default.fileExists(atPath: link) { return link }
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }

    /// Called by the agents' hooks. Reads the hook payload on stdin and
    /// records one line of activity. Always exits 0 and never blocks a turn.
    /// With --allow it also prints an allow decision — Antigravity's
    /// PreToolUse hook is synchronous and waits for one.
    static func event(_ args: [String]) -> Never {
        let allow = args.contains("--allow")
        func finish() -> Never {
            if allow { print("{\"decision\":\"allow\"}") }
            exit(0)
        }
        guard let name = args.first(where: { !$0.hasPrefix("-") }) else { finish() }
        var tool = ""
        var recorded = name
        var session = ""
        var project = ""
        var detail = ""
        var cwd = ""
        if isatty(FileHandle.standardInput.fileDescriptor) == 0 {  // only when piped
            let data = FileHandle.standardInput.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Antigravity nests the name inside a camelCase toolCall.
                tool =
                    json["tool_name"] as? String
                    ?? (json["toolCall"] as? [String: Any])?["name"] as? String ?? ""
                // Only Claude Code has a dedicated failure event. Everywhere
                // else the failure is in the result payload, so read it and
                // report the same thing.
                if name == "PostToolUse", toolFailed(json) { recorded = "PostToolUseFailure" }
                // Who and where, for the activity bubbles. Each agent spells
                // these its own way.
                session =
                    json["session_id"] as? String
                    ?? json["conversation_id"] as? String
                    ?? json["conversationId"] as? String ?? ""
                cwd =
                    json["cwd"] as? String
                    ?? (json["workspace_roots"] as? [String])?.first
                    ?? (json["workspacePaths"] as? [String])?.first ?? ""
                if !cwd.isEmpty {
                    // a folder name may itself contain "|"; keep it out of the
                    // pipe-delimited line
                    project = URL(fileURLWithPath: cwd).lastPathComponent
                        .replacingOccurrences(of: "|", with: " ")
                        .split(whereSeparator: \.isNewline).joined(separator: " ")
                }
                detail = eventDetail(json)
            }
        }
        let dir = SkinStore.configDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "\(recorded)|\(tool)|\(Int(Date().timeIntervalSince1970))\n"
        try? line.write(to: dir.appendingPathComponent("state"), atomically: true, encoding: .utf8)

        // Per-session activity, one small file each, so concurrent agents
        // never fight over one file. SessionEnd retires the session.
        if !session.isEmpty {
            let safe = String(
                session.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" })
            let file = dir.appendingPathComponent("sessions/\(safe)")
            if recorded == "SessionEnd" {
                try? FileManager.default.removeItem(at: file)
            } else {
                try? FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                // cwd is base64'd so a path with "|" or spaces survives the
                // pipe-delimited line intact.
                let encodedCwd = Data(cwd.utf8).base64EncodedString()
                // the terminal or IDE running this agent, so a click can bring
                // its window (and Space) to the front — "bundleID,pid".
                let app = owningApp().map { "\($0.bundleID),\($0.pid)" } ?? ""
                let encodedApp = Data(app.utf8).base64EncodedString()
                let entry =
                    "\(recorded)|\(tool)|\(Int(Date().timeIntervalSince1970))"
                    + "|\(project)|\(detail)|\(encodedCwd)|\(encodedApp)\n"
                try? entry.write(to: file, atomically: true, encoding: .utf8)
            }
        }

        recordStat(event: recorded, session: session, tool: tool)
        finish()
    }

    /// A tiny daily tally for `pet stats`: tools run, sessions seen, and the
    /// span from first to last event. One JSON object keyed by day.
    static func recordStat(event: String, session: String, tool: String) {
        let file = SkinStore.configDir.appendingPathComponent("stats.json")
        var all =
            (try? Data(contentsOf: file)).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]]
            } ?? [:]

        let day = Self.dayKey()
        var today = all[day] ?? [:]
        let now = Int(Date().timeIntervalSince1970)

        // a tool run is one PreToolUse
        if event == "PreToolUse" { today["tools"] = (today["tools"] as? Int ?? 0) + 1 }
        if event == "PostToolUseFailure" || event == "StopFailure" {
            today["failures"] = (today["failures"] as? Int ?? 0) + 1
        }
        if !session.isEmpty {
            var seen = Set(today["sessions"] as? [String] ?? [])
            seen.insert(session)
            today["sessions"] = Array(seen)
        }
        if today["first"] == nil { today["first"] = now }
        today["last"] = now
        all[day] = today

        // keep the file from growing without bound — the last 60 days is plenty
        if all.count > 60 {
            for key in all.keys.sorted().prefix(all.count - 60) { all.removeValue(forKey: key) }
        }
        if let out = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]) {
            try? out.write(to: file)
        }
    }

    /// The GUI app that ultimately launched this agent — the terminal or IDE
    /// window the user would want raised. Walks the parent-process chain from
    /// `pet event` (child of the agent, child of the shell, child of the app)
    /// to the first ancestor that is a regular app with a bundle id.
    static func owningApp() -> (bundleID: String, pid: Int32)? {
        var pid = getppid()
        for _ in 0..<12 {  // a safety bound on the walk
            guard pid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: pid),
                app.activationPolicy == .regular, let bundleID = app.bundleIdentifier
            {
                return (bundleID, pid)
            }
            guard let parent = parentPID(of: pid), parent != pid else { break }
            pid = parent
        }
        return nil
    }

    /// The parent PID of a process, via sysctl — no private API.
    private static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// yyyy-MM-dd in the local calendar, without pulling in a DateFormatter.
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// One human line saying what the agent is doing, straight from the
    /// payload: what it was asked, or what the tool it is running is up to.
    /// Cleaned of the state format's separators and kept short.
    static func eventDetail(_ json: [String: Any]) -> String {
        var text = ""
        if let prompt = json["prompt"] as? String {
            text = prompt
        } else if let input = json["tool_input"] as? [String: Any]
            ?? (json["toolCall"] as? [String: Any])?["args"] as? [String: Any]
        {
            // the most human field a tool call offers
            if let description = input["description"] as? String {
                text = description
            } else if let path = (input["file_path"] as? String ?? input["filePath"] as? String) {
                text = URL(fileURLWithPath: path).lastPathComponent
            } else if let command = input["command"] as? String {
                text = command
            } else if let pattern = input["pattern"] as? String {
                text = pattern
            } else if let url = input["url"] as? String {
                text = url
            }
        }
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "|", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flattened.prefix(90))
    }

    /// Did the tool this event describes fail? Agents word it differently:
    /// Claude Code reports success, Gemini CLI puts an error inside
    /// tool_response, others may set one at the top level.
    static func toolFailed(_ json: [String: Any]) -> Bool {
        if let response = json["tool_response"] as? [String: Any] {
            if let error = response["error"], !(error is NSNull) { return true }
            if let ok = response["success"] as? Bool, !ok { return true }
            if let status = response["status"] as? String,
                status.lowercased().contains("error") || status.lowercased().contains("fail")
            {
                return true
            }
        }
        if let error = json["error"], !(error is NSNull) { return true }
        return false
    }

    static var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Prefs.domain)
    }

    static func help() {
        print(
            """
            pet — Desktop Pet

            USAGE
              pet <command> [arguments]

            APP
              status                 what the pet is doing right now
              start | stop | restart
              show | hide            show or hide the pet
              tray show | tray hide  show or hide the menu bar icon
              bubbles show | hide    the activity bubbles above the pet
              stats                  today's sessions, tools and active time
              size [50…200 | reset]  how big the pet is drawn

            SKINS AND SPRITE PETS
              skins                  list everything installed
              skin <id>              switch to a skin or sprite pet
              skins dir              print the skins folder
              pets                   list sprite pets (codex-pets.net packs)
              pets install <id>      download one from codex-pets.net
              pets install <path>    install a local folder or .zip
              pets remove <id>
              pets dir               print the sprite pet folder

            CONFIG
              config                 print the config folder and where it came from
              config set <path>      use a different config folder
              config reset           go back to ~/.config/pet

            AGENT PLUGIN
              plugin install [agent]   make the pet react to your coding agent
                                       agent = claude | codex | gemini | opencode
                                             | antigravity | cursor | pi
              plugin uninstall [agent] default: every agent found
              plugin status
              --path <dir>             a config folder other than the default;
                                       repeatable
              event <name>             record activity; this is what the hooks call

            OTHER
              render <file>          render every skin and pose to a PNG sheet
              icon [size] <file>     render the app icon
              uninstall [--all]      remove the app and this CLI (--all: config too)
              version | help
            """)
    }

    static func run(_ argv: [String]) -> Never {
        var args = Array(argv.dropFirst())
        let cmd = args.removeFirst()
        switch cmd {
        case "help", "--help", "-h": help()
        case "version", "--version": print("pet \(Build.version)")
        case "status": status()
        case "start": start()
        case "stop": stop()
        case "restart": stop(); Thread.sleep(forTimeInterval: 0.6); start()
        case "show": setHidden(false)
        case "hide": setHidden(true)
        case "tray": tray(args.first)
        case "bubbles": bubbles(args.first)
        case "stats": stats()
        case "size": size(args.first)
        case "skins": args.first == "dir" ? print(SkinStore.userDir.path) : listSkins()
        case "pets": pets(args)
        case "skin": setSkin(args.first)
        case "config": config(args)
        case "event": event(args)
        case "plugin": plugin(args)
        case "uninstall": uninstall(all: args.contains("--all"))
        default: fail("unknown command \"\(cmd)\" — try: pet help")
        }
        exit(0)
    }
}
