//  HookHost.swift
//  Desktop Pet
//
//  The coding agents whose lifecycle hooks can drive the pet.

import Cocoa

struct HookEvent {
    let host: String
    let pet: String
    let matcher: String?
    init(_ host: String, as pet: String? = nil, matcher: String? = nil) {
        self.host = host
        self.pet = pet ?? host
        self.matcher = matcher
    }
}

/// A coding agent whose lifecycle hooks can drive the pet.
///
/// Most agents take JSON config listing commands to run. opencode instead
/// loads JavaScript plugins, so it gets a generated plugin file.

struct HookHost {
    enum Kind {
        /// JSON config with a "hooks" object, as Claude Code, Codex and
        /// Gemini CLI all use.
        case json(files: [URL], events: [HookEvent], timeout: Int, supportsAsync: Bool)
        /// A JavaScript plugin file, written to `file`. `alternates` are other
        /// locations an older install may have used; they are cleaned up too.
        case plugin(file: URL, alternates: [URL])
    }

    let id: String
    let name: String
    /// Name of the config file inside a config folder.
    let fileName: String
    let kind: Kind

    var files: [URL] {
        switch kind {
        case .json(let files, _, _, _): return files
        case .plugin(let file, _): return [file]
        }
    }

    var events: [HookEvent] {
        if case .json(_, let events, _, _) = kind { return events }
        return []
    }

    /// True when the agent appears to be installed for this user.
    var isPresent: Bool {
        switch kind {
        case .json(let files, _, _, _):
            return files.contains {
                FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path)
            }
        case .plugin(let file, _):
            // the plugin folder is ours to create; the agent's config root is
            // what says whether the agent itself is here
            let root = file.deletingLastPathComponent().deletingLastPathComponent()
            return FileManager.default.fileExists(atPath: root.path)
        }
    }

    /// Plugin hosts write the pet's state file themselves.
    var callsTheCLI: Bool { if case .json = kind { return true } else { return false } }

    static var defaultClaudeDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    }

    /// Other ~/.claude-* folders on this machine. Never touched automatically;
    /// reported by `pet plugin status` so an old install is not forgotten.
    static func otherClaudeDirs(besides managedPaths: Set<String>) -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let entries =
            (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory())) ?? []
        return entries.sorted()
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { home.appendingPathComponent($0).standardizedFileURL }
            .filter { url in
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return exists && isDir.boolValue && !managedPaths.contains(url.path)
            }
    }

    /// Same host, pointed at folders given with --path. A path ending in the
    /// host's file extension is taken as the config file itself.
    func targeting(_ paths: [URL]) -> HookHost {
        let resolved = paths.map { path -> URL in
            let ext = path.pathExtension.lowercased()
            return (ext == "json" || ext == "js") ? path : path.appendingPathComponent(fileName)
        }
        switch kind {
        case .json(_, let events, let timeout, let supportsAsync):
            return HookHost(
                id: id, name: name, fileName: fileName,
                kind: .json(
                    files: resolved, events: events,
                    timeout: timeout, supportsAsync: supportsAsync))
        case .plugin(_, let alternates):
            return HookHost(
                id: id, name: name, fileName: fileName,
                kind: .plugin(file: resolved[0], alternates: alternates))
        }
    }

    static var claude: HookHost {
        HookHost(
            id: "claude", name: "Claude Code", fileName: "settings.json",
            kind: .json(
                files: [defaultClaudeDir.appendingPathComponent("settings.json")],
                events: [
                    HookEvent("SessionStart"), HookEvent("UserPromptSubmit"),
                    HookEvent("PreToolUse", matcher: "*"),
                    HookEvent("PostToolUse", matcher: "*"),
                    HookEvent("PostToolUseFailure", matcher: "*"),
                    HookEvent("StopFailure"),
                    HookEvent("Notification"), HookEvent("Stop"),
                    HookEvent("SessionEnd"),
                ],
                timeout: 5, supportsAsync: true))
    }

    /// Codex keeps hooks in ~/.codex/hooks.json. Matchers there are regexes,
    /// so they are omitted, which matches every tool.
    static var codex: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        return HookHost(
            id: "codex", name: "Codex", fileName: "hooks.json",
            kind: .json(
                files: [dir.appendingPathComponent("hooks.json")],
                events: [
                    HookEvent("SessionStart"), HookEvent("UserPromptSubmit"),
                    HookEvent("PreToolUse"), HookEvent("PostToolUse"),
                    HookEvent("PermissionRequest", as: "Notification"),
                    HookEvent("Stop"), HookEvent("SessionEnd"),
                ],
                timeout: 5, supportsAsync: true))
    }

    /// Gemini CLI uses its own event vocabulary, its timeout is in
    /// milliseconds, and it has no async flag — hooks there block briefly.
    static var gemini: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini")
        return HookHost(
            id: "gemini", name: "Gemini CLI", fileName: "settings.json",
            kind: .json(
                files: [dir.appendingPathComponent("settings.json")],
                events: [
                    HookEvent("SessionStart"),
                    HookEvent("BeforeAgent", as: "UserPromptSubmit"),
                    HookEvent("BeforeTool", as: "PreToolUse"),
                    HookEvent("AfterTool", as: "PostToolUse"),
                    HookEvent("AfterAgent", as: "Stop"),
                    HookEvent("Notification"), HookEvent("SessionEnd"),
                ],
                timeout: 5000, supportsAsync: false))
    }

    /// opencode loads JavaScript plugins. Both plugin/ and plugins/ are read
    /// (verified against 1.18.x), so install into one and clean both.
    static var opencode: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/opencode")
        return HookHost(
            id: "opencode", name: "opencode", fileName: "pet.js",
            kind: .plugin(
                file: dir.appendingPathComponent("plugin/pet.js"),
                alternates: [dir.appendingPathComponent("plugins/pet.js")]))
    }

    static var all: [HookHost] { [.claude, .codex, .gemini, .opencode] }
    static func named(_ id: String) -> HookHost? { all.first { $0.id == id } }
}

/// The JavaScript plugin written into opencode's plugin folder. It writes the
/// pet's state file directly — no process to spawn per event.
