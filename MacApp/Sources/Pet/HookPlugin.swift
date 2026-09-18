//  HookPlugin.swift
//  Desktop Pet
//
//  Registering and removing the pet's hooks in an agent's config.

import Cocoa

enum HookPlugin {
    /// Claude runs the `pet` CLI directly — there is no generated script.
    static var command: String {
        let path = CLI.installedCommandPath
        return (path.contains(" ") ? "\"\(path)\"" : path) + " event"
    }

    /// Recognises our hook entries: the current CLI form, an install that
    /// lives somewhere else, and the pre-1.0 generated script.
    ///
    /// Deliberately strict. Matching loosely would make install and uninstall
    /// delete somebody else's hook — a command like `/opt/tools/snippet event
    /// PreToolUse` must not look like ours just because it ends in "pet".
    static func isOurCommand(_ command: String) -> Bool {
        if command.contains("pet-hook.sh") { return true }  // legacy

        let text = command.trimmingCharacters(in: .whitespaces)
        let executable: String
        if text.hasPrefix("\"") {  // quoted path
            let body = text.dropFirst()
            guard let end = body.firstIndex(of: "\"") else { return false }
            executable = String(body[body.startIndex..<end])
        } else {
            executable = String(text.split(separator: " ").first ?? "")
        }

        // The program itself must be the pet, and it must be the event subcommand.
        let name = URL(fileURLWithPath: executable).lastPathComponent
        guard name == "pet" || name == "Pet" else { return false }
        let arguments = text.dropFirst(
            text.hasPrefix("\"")
                ? executable.count + 2
                : executable.count)
        return arguments.trimmingCharacters(in: .whitespaces).hasPrefix("event ")
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        let hooks = group["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { isOurCommand($0["command"] as? String ?? "") }
    }

    enum MergeResult { case changed(Int), unchanged, unreadable }

    /// The command registered for one event.
    static func command(for event: HookEvent) -> String {
        "\(command) \(event.pet)" + (event.flags.map { " \($0)" } ?? "")
    }

    /// Merge our entry into one event's matcher-group list, as the nested and
    /// named dialects lay them out. Returns how many changes were made.
    private static func mergeGroups(
        _ list: inout [[String: Any]], event: HookEvent, timeout: Int,
        supportsAsync: Bool, remove: Bool
    ) -> Int {
        var changed = 0
        let want = command(for: event)
        if remove {
            let kept = list.filter { !isOurs($0) }
            if kept.count != list.count { changed += 1 }
            list = kept
            return changed
        }
        // drop our entries that point elsewhere (an older install)
        list = list.filter { group in
            guard isOurs(group) else { return true }
            let correct = (group["hooks"] as? [[String: Any]] ?? [])
                .contains { ($0["command"] as? String) == want }
            if !correct { changed += 1 }
            return correct
        }
        if !list.contains(where: isOurs) {
            var handler: [String: Any] = [
                "type": "command", "command": want,
                "timeout": timeout,
            ]
            if supportsAsync { handler["async"] = true }  // only where supported
            var entry: [String: Any] = ["hooks": [handler]]
            if let matcher = event.matcher { entry["matcher"] = matcher }
            list.append(entry)
            changed += 1
        }
        return changed
    }

    /// The same for the flat dialect, where handlers sit directly in the list.
    private static func mergeFlat(
        _ list: inout [[String: Any]], event: HookEvent, timeout: Int, remove: Bool
    ) -> Int {
        var changed = 0
        let want = command(for: event)
        let ours = { (handler: [String: Any]) in
            isOurCommand(handler["command"] as? String ?? "")
        }
        if remove {
            let kept = list.filter { !ours($0) }
            if kept.count != list.count { changed += 1 }
            list = kept
            return changed
        }
        list = list.filter { handler in
            guard ours(handler) else { return true }
            let correct = (handler["command"] as? String) == want
            if !correct { changed += 1 }
            return correct
        }
        if !list.contains(where: ours) {
            list.append(["command": want, "timeout": timeout])
            changed += 1
        }
        return changed
    }

    /// Reconciles our entries in one config file and leaves the rest alone.
    static func merge(
        file url: URL, events: [HookEvent], timeout: Int,
        supportsAsync: Bool, dialect: HookHost.Dialect, remove: Bool
    ) -> MergeResult {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return .unreadable  // never clobber a file we cannot parse
            }
            root = parsed
        }
        var changed = 0

        switch dialect {
        case .nested:
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for event in events {
                var list = hooks[event.host] as? [[String: Any]] ?? []
                changed += mergeGroups(
                    &list, event: event, timeout: timeout,
                    supportsAsync: supportsAsync, remove: remove)
                if list.isEmpty {
                    hooks.removeValue(forKey: event.host)
                } else {
                    hooks[event.host] = list
                }
            }
            if remove && hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }

        case .named(let key):
            var entry = root[key] as? [String: Any] ?? [:]
            for event in events {
                var list = entry[event.host] as? [[String: Any]] ?? []
                changed += mergeGroups(
                    &list, event: event, timeout: timeout,
                    supportsAsync: supportsAsync, remove: remove)
                if list.isEmpty {
                    entry.removeValue(forKey: event.host)
                } else {
                    entry[event.host] = list
                }
            }
            if remove {
                // drop the whole entry once no event list is left in it
                if entry.values.contains(where: { $0 is [[String: Any]] }) {
                    root[key] = entry
                } else {
                    root.removeValue(forKey: key)
                }
            } else {
                entry["enabled"] = true
                root[key] = entry
            }

        case .flat:
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for event in events {
                var list = hooks[event.host] as? [[String: Any]] ?? []
                changed += mergeFlat(&list, event: event, timeout: timeout, remove: remove)
                if list.isEmpty {
                    hooks.removeValue(forKey: event.host)
                } else {
                    hooks[event.host] = list
                }
            }
            if remove && hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
                if root["version"] == nil { root["version"] = 1 }  // Cursor requires it
            }
        }

        guard changed > 0 else { return .unchanged }

        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak-pet")
            try? FileManager.default.removeItem(at: backup)  // keep the latest backup
            try? FileManager.default.copyItem(at: url, to: backup)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        }
        guard
            let out = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else {
            return .unreadable
        }
        try? out.write(to: url)
        return .changed(changed)
    }

    static func registeredCount(in file: URL, dialect: HookHost.Dialect = .nested) -> Int {
        guard let data = try? Data(contentsOf: file),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return 0 }
        let container: [String: Any]
        switch dialect {
        case .nested, .flat:
            container = root["hooks"] as? [String: Any] ?? [:]
        case .named(let key):
            container = root[key] as? [String: Any] ?? [:]
        }
        if case .flat = dialect {
            return container.values.reduce(0) { total, value in
                total
                    + ((value as? [[String: Any]] ?? [])
                        .filter { isOurCommand($0["command"] as? String ?? "") }.count)
            }
        }
        return container.values.reduce(0) { total, value in
            total + ((value as? [[String: Any]] ?? []).filter(isOurs).count)
        }
    }

    static func isRegistered(_ host: HookHost) -> Bool {
        switch host.kind {
        case .json:
            return host.files.contains { registeredCount(in: $0, dialect: host.dialect) > 0 }
        case .plugin(let file, let alternates, _):
            return ([file] + alternates).contains {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
    }

    static var isRegisteredAnywhere: Bool { HookHost.all.contains(where: isRegistered) }

    static func apply(_ host: HookHost, remove: Bool) {
        print("\(host.name):")
        switch host.kind {
        case .json(let files, let events, let timeout, let supportsAsync, let dialect):
            for file in files {
                let label = CLI.tilde(file.deletingLastPathComponent())
                if remove, !FileManager.default.fileExists(atPath: file.path) {
                    print("  ·  \(label) — nothing to remove")
                    continue
                }
                switch merge(
                    file: file, events: events, timeout: timeout,
                    supportsAsync: supportsAsync, dialect: dialect, remove: remove)
                {
                case .unreadable:
                    print("  !  \(label) — \(file.lastPathComponent) unreadable, left untouched")
                case .unchanged: print("  ·  \(label) already up to date")
                case .changed(let n):
                    print("  ✓  \(label) — \(n) event(s) \(remove ? "removed" : "updated")")
                }
            }
        case .plugin(let file, let alternates, let source):
            if remove {
                var removed = false
                for url in [file] + alternates
                where FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                    print("  ✓  removed \(CLI.tilde(url))")
                    removed = true
                }
                if !removed { print("  ·  nothing to remove") }
            } else {
                // a stale copy in the other plugin folder would fire twice
                for url in alternates where FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                    print("  ✓  removed duplicate \(CLI.tilde(url))")
                }
                do {
                    try FileManager.default.createDirectory(
                        at: file.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try source.write(to: file, atomically: true, encoding: .utf8)
                    print("  ✓  \(CLI.tilde(file))")
                } catch {
                    print(
                        "  !  could not write \(CLI.tilde(file)): \(error.localizedDescription)")
                }
            }
        }
        applyCommands(host, remove: remove)
        if host.id == "claude" {
            for dir in claudeSettingsDirs(host) {
                mergeStatusLine(claudeDir: dir, remove: remove)
            }
        }
    }

    /// The folders holding a settings.json we just touched, so the status
    /// line install lands beside the same file(s) — including every
    /// `--path` the hooks were just registered into.
    private static func claudeSettingsDirs(_ host: HookHost) -> [URL] {
        guard case .json(let files, _, _, _, _) = host.kind else { return [] }
        return files.map { $0.deletingLastPathComponent() }
    }

    // MARK: status line

    /// Our own claim on the statusLine slot: same strict-ownership rule as a
    /// hook — the executable must be the pet, and its first argument must be
    /// `statusline`. A user's own script never accidentally looks like ours.
    static func isOurStatusLineCommand(_ command: String) -> Bool {
        let text = command.trimmingCharacters(in: .whitespaces)
        let executable: String
        if text.hasPrefix("\"") {
            let body = text.dropFirst()
            guard let end = body.firstIndex(of: "\"") else { return false }
            executable = String(body[body.startIndex..<end])
        } else {
            executable = String(text.split(separator: " ").first ?? "")
        }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        guard name == "pet" || name == "Pet" else { return false }
        let arguments = text.dropFirst(
            text.hasPrefix("\"") ? executable.count + 2 : executable.count)
        return arguments.trimmingCharacters(in: .whitespaces).hasPrefix("statusline")
    }

    static func statusLineCommand(claudeDir: URL) -> String {
        let path = CLI.installedCommandPath
        let quoted = path.contains(" ") ? "\"\(path)\"" : path
        let dirArg = claudeDir.path.contains(" ") ? "\"\(claudeDir.path)\"" : claudeDir.path
        return "\(quoted) statusline --claude-dir \(dirArg)"
    }

    private static func previousStatusLineMarker(_ claudeDir: URL) -> URL {
        claudeDir.appendingPathComponent(".pet-statusline-previous.json")
    }

    /// What `pet statusline` chains to, when we are wrapping somebody else's
    /// statusline rather than being the only one.
    static func previousStatusLineCommand(claudeDir: URL) -> String? {
        guard let data = try? Data(contentsOf: previousStatusLineMarker(claudeDir)),
            let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let command = saved["command"] as? String
        else { return nil }
        return command
    }

    /// Installs `pet statusline` into settings.json's single `statusLine`
    /// slot, remembering whatever was there so uninstall can give it back.
    /// Never touches a slot that already holds something we do not
    /// recognise as ours on the way out — only ever our own entry is
    /// replaced or restored.
    static func mergeStatusLine(claudeDir: URL, remove: Bool) {
        let settingsFile = claudeDir.appendingPathComponent("settings.json")
        let marker = previousStatusLineMarker(claudeDir)
        let label = CLI.tilde(settingsFile.deletingLastPathComponent())

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsFile), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                print("  !  \(label) — settings.json unreadable, status line left untouched")
                return
            }
            root = parsed
        } else if remove {
            return  // nothing to remove
        }

        let existing = root["statusLine"] as? [String: Any]
        let oursNow =
            existing.map { isOurStatusLineCommand($0["command"] as? String ?? "") }
            ?? false

        if remove {
            guard oursNow else { return }  // never ours; leave whatever is there alone
            if let data = try? Data(contentsOf: marker),
                let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                root["statusLine"] = previous
                print("  ✓  \(label) — status line restored")
            } else {
                root.removeValue(forKey: "statusLine")
                print("  ✓  \(label) — status line removed")
            }
            try? FileManager.default.removeItem(at: marker)
            writeSettings(root, to: settingsFile)
            return
        }

        guard !oursNow else { return }  // already installed
        if let existing {
            // somebody else's statusline: remember it so uninstall gives it back
            if let data = try? JSONSerialization.data(withJSONObject: existing) {
                try? data.write(to: marker)
            }
        } else {
            try? FileManager.default.removeItem(at: marker)  // nothing to chain to
        }
        root["statusLine"] = [
            "type": "command", "command": statusLineCommand(claudeDir: claudeDir),
        ]
        writeSettings(root, to: settingsFile)
        print("  ✓  \(label) — status line installed (Claude's session/week usage)")
    }

    private static func writeSettings(_ root: [String: Any], to url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak-pet")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard
            let out = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }
        try? out.write(to: url)
    }

    /// The create-pet and create-sprite files — skills for Claude Code and
    /// Codex, command files elsewhere — kept in step with the hooks. Only
    /// files at our exact paths are ever touched.
    static func applyCommands(_ host: HookHost, remove: Bool) {
        for (path, source) in host.commandFiles {
            let file = host.configRoot.appendingPathComponent(path)
            let exists = FileManager.default.fileExists(atPath: file.path)
            if remove {
                if exists {
                    try? FileManager.default.removeItem(at: file)
                    // a skill leaves its own folder behind; take it too when
                    // the SKILL.md was all it held
                    let parent = file.deletingLastPathComponent()
                    if file.lastPathComponent == "SKILL.md",
                        let left = try? FileManager.default.contentsOfDirectory(
                            atPath: parent.path),
                        left.filter({ $0 != ".DS_Store" }).isEmpty
                    {
                        try? FileManager.default.removeItem(at: parent)
                    }
                    print("  ✓  removed \(CLI.tilde(file))")
                }
                continue
            }
            if exists, (try? String(contentsOf: file, encoding: .utf8)) == source {
                print("  ·  \(CLI.tilde(file)) already up to date")
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try source.write(to: file, atomically: true, encoding: .utf8)
                print("  ✓  \(CLI.tilde(file))")
            } catch {
                print("  !  could not write \(CLI.tilde(file)): \(error.localizedDescription)")
            }
        }
    }

    static func install(_ hosts: [HookHost]) {
        try? FileManager.default.createDirectory(
            at: SkinStore.configDir,
            withIntermediateDirectories: true)
        if hosts.contains(where: \.callsTheCLI) {
            print("hook command: \(command) <event>")
        }
        print("")
        for host in hosts { apply(host, remove: false) }
        cleanLegacy()
        print("")
        print(
            "Start a new session in \(hosts.map(\.name).joined(separator: " / ")) — "
                + "the pet will start reacting.")
    }

    static func uninstall(_ hosts: [HookHost]) {
        for host in hosts { apply(host, remove: true) }
        cleanLegacy()
    }

    /// Earlier versions generated a shell script; the CLI replaces it.
    static func cleanLegacy() {
        let script = SkinStore.configDir.appendingPathComponent("pet-hook.sh")
        if FileManager.default.fileExists(atPath: script.path) {
            try? FileManager.default.removeItem(at: script)
            print("  ✓  removed the old \(CLI.tilde(script))")
        }
        let older = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/pet")
        if FileManager.default.fileExists(atPath: older.appendingPathComponent("pet-hook.sh").path)
        {
            try? FileManager.default.removeItem(at: older)
            print("  ✓  removed the old hook at ~/.claude/pet")
        }
    }

    static func status() {
        print(
            "hook command: \(command) <event>   "
                + "(opencode and pi write the state file directly)")
        for host in HookHost.all {
            print("")
            print("\(host.name)\(host.isPresent ? "" : "  (not installed)"):")
            switch host.kind {
            case .json(let files, _, _, _, _):
                for file in files {
                    let label = CLI.tilde(file.deletingLastPathComponent())
                    let n = registeredCount(in: file, dialect: host.dialect)
                    print("  \(label): \(n == 0 ? "not registered" : "\(n) hook entries")")
                }
            case .plugin(let file, let alternates, _):
                let installed = ([file] + alternates).filter {
                    FileManager.default.fileExists(atPath: $0.path)
                }
                let location =
                    installed.isEmpty
                    ? "not registered"
                    : installed.map(CLI.tilde).joined(separator: ", ")
                print("  \(location)")
            }
            let commands = host.commandFiles
                .map { host.configRoot.appendingPathComponent($0.path) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !commands.isEmpty {
                print("  commands: \(commands.map(\.lastPathComponent).joined(separator: ", "))")
            }
            if host.id == "claude" {
                let managed = Set(
                    host.files.map { $0.deletingLastPathComponent().standardizedFileURL.path })
                let stray = HookHost.otherClaudeDirs(besides: managed).filter {
                    registeredCount(in: $0.appendingPathComponent(host.fileName)) > 0
                }
                for dir in stray {
                    print("  !  \(CLI.tilde(dir)) also has pet hooks")
                    print(
                        "     clean it with `pet plugin uninstall claude --path \(CLI.tilde(dir))`")
                }
            }
        }
    }
}

// MARK: - Installing sprite pets

/// Shared by the CLI and the menu, so both accept the same things and behave
/// the same way.
