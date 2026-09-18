//  HookHost.swift
//  Desktop Pet
//
//  The coding agents whose lifecycle hooks can drive the pet.

import Cocoa

struct HookEvent {
    let host: String
    let pet: String
    let matcher: String?
    /// Extra arguments after the event name, e.g. "--allow" for hosts whose
    /// tool events block until they hear a decision on stdout.
    let flags: String?
    init(_ host: String, as pet: String? = nil, matcher: String? = nil, flags: String? = nil) {
        self.host = host
        self.pet = pet ?? host
        self.matcher = matcher
        self.flags = flags
    }
}

/// A coding agent whose lifecycle hooks can drive the pet.
///
/// Most agents take JSON config listing commands to run. opencode and pi
/// instead load script plugins, so they get a generated plugin file.

struct HookHost {
    /// How a JSON config lays out its hooks. The inner handler shape is the
    /// same everywhere; what differs is where the event lists live.
    enum Dialect {
        /// `{"hooks": {Event: [{matcher?, hooks: [handler]}]}}` — Claude Code,
        /// Codex and Gemini CLI.
        case nested
        /// `{"version": 1, "hooks": {event: [handler]}}` — Cursor. Handlers
        /// sit directly in the event list, no matcher groups.
        case flat
        /// `{"<name>": {"enabled": true, Event: [{matcher?, hooks: [handler]}]}}`
        /// — Antigravity. The top level is keyed by hook name, so the pet owns
        /// exactly one entry and never walks the others.
        case named(String)
    }

    enum Kind {
        /// JSON config listing commands to run; see Dialect for the layout.
        case json(
            files: [URL], events: [HookEvent], timeout: Int, supportsAsync: Bool,
            dialect: Dialect)
        /// A script plugin written to `file`. `alternates` are other locations
        /// an older install may have used; they are cleaned up too.
        case plugin(file: URL, alternates: [URL], source: String)
    }

    let id: String
    let name: String
    /// Name of the config file inside a config folder.
    let fileName: String
    let kind: Kind
    /// Paths that say the agent is installed, for agents whose config folder
    /// alone cannot (Antigravity shares ~/.gemini with Gemini CLI). Empty
    /// means the config folder decides.
    var presenceMarkers: [URL] = []
    /// Command files (/pet-skin, /pet-sprite) installed next to the hooks,
    /// as paths relative to `configRoot`. Empty when the agent has no
    /// command mechanism.
    var commandFiles: [(path: String, source: String)] = []

    /// The folder command paths resolve against.
    var configRoot: URL {
        switch kind {
        case .json(let files, _, _, _, _):
            return files[0].deletingLastPathComponent()
        case .plugin(let file, _, _):
            return file.deletingLastPathComponent().deletingLastPathComponent()
        }
    }

    var files: [URL] {
        switch kind {
        case .json(let files, _, _, _, _): return files
        case .plugin(let file, _, _): return [file]
        }
    }

    var events: [HookEvent] {
        if case .json(_, let events, _, _, _) = kind { return events }
        return []
    }

    var dialect: Dialect {
        if case .json(_, _, _, _, let dialect) = kind { return dialect }
        return .nested
    }

    /// True when the agent appears to be installed for this user.
    var isPresent: Bool {
        if !presenceMarkers.isEmpty {
            return presenceMarkers.contains {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
        switch kind {
        case .json(let files, _, _, _, _):
            return files.contains {
                FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path)
            }
        case .plugin(let file, _, _):
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
            return (ext == "json" || ext == "js" || ext == "ts")
                ? path : path.appendingPathComponent(fileName)
        }
        switch kind {
        case .json(_, let events, let timeout, let supportsAsync, let dialect):
            return HookHost(
                id: id, name: name, fileName: fileName,
                kind: .json(
                    files: resolved, events: events,
                    timeout: timeout, supportsAsync: supportsAsync, dialect: dialect),
                presenceMarkers: presenceMarkers, commandFiles: commandFiles)
        case .plugin(_, let alternates, let source):
            return HookHost(
                id: id, name: name, fileName: fileName,
                kind: .plugin(file: resolved[0], alternates: alternates, source: source),
                presenceMarkers: presenceMarkers, commandFiles: commandFiles)
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
                timeout: 5, supportsAsync: true, dialect: .nested),
            commandFiles: AgentCommands.files(folder: "skills", args: "", style: .skill))
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
                timeout: 5, supportsAsync: true, dialect: .nested),
            commandFiles: AgentCommands.files(
                folder: "skills", args: "", style: .skill, hatchPet: true))
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
                timeout: 5000, supportsAsync: false, dialect: .nested),
            commandFiles: AgentCommands.files(
                folder: "commands", args: "{{args}}", style: .toml))
    }

    /// Antigravity's hooks.json lives under ~/.gemini but is its own format —
    /// Antigravity 1.1+ ignores Gemini CLI's settings.json entirely. Hooks are
    /// synchronous, and PreToolUse blocks until it reads a decision on stdout,
    /// so that event runs `pet event PreToolUse --allow`. There is no
    /// SessionStart or Notification equivalent.
    static var antigravity: HookHost {
        let home = NSHomeDirectory()
        return HookHost(
            id: "antigravity", name: "Antigravity", fileName: "hooks.json",
            kind: .json(
                files: [
                    URL(fileURLWithPath: home).appendingPathComponent(".gemini/config/hooks.json")
                ],
                events: [
                    HookEvent("PreInvocation", as: "UserPromptSubmit"),
                    HookEvent("PreToolUse", flags: "--allow"),
                    HookEvent("PostToolUse"),
                    HookEvent("PostInvocation", as: "Stop"),
                    HookEvent("Stop", as: "SessionEnd"),
                ],
                timeout: 5, supportsAsync: false, dialect: .named("pet")),
            presenceMarkers: [
                URL(fileURLWithPath: "/Applications/Antigravity.app"),
                URL(fileURLWithPath: home + "/Applications/Antigravity.app"),
                URL(fileURLWithPath: home + "/.antigravity"),
            ])
    }

    /// Cursor reads ~/.cursor/hooks.json for both the IDE and its CLI.
    /// Handlers sit directly in each event's list, `version: 1` is required,
    /// and hooks fail open — an observer that prints nothing never blocks.
    /// There is no Notification equivalent.
    static var cursor: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cursor")
        return HookHost(
            id: "cursor", name: "Cursor", fileName: "hooks.json",
            kind: .json(
                files: [dir.appendingPathComponent("hooks.json")],
                events: [
                    HookEvent("sessionStart", as: "SessionStart"),
                    HookEvent("beforeSubmitPrompt", as: "UserPromptSubmit"),
                    HookEvent("preToolUse", as: "PreToolUse"),
                    HookEvent("postToolUse", as: "PostToolUse"),
                    HookEvent("postToolUseFailure", as: "PostToolUseFailure"),
                    HookEvent("stop", as: "Stop"),
                    HookEvent("sessionEnd", as: "SessionEnd"),
                ],
                timeout: 5, supportsAsync: false, dialect: .flat),
            commandFiles: AgentCommands.files(
                folder: "commands", args: "the request written after the command",
                style: .frontmatter))
    }

    /// opencode loads JavaScript plugins. Both plugin/ and plugins/ are read
    /// (verified against 1.18.x), so install into one and clean both.
    static var opencode: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/opencode")
        return HookHost(
            id: "opencode", name: "opencode", fileName: "pet.js",
            kind: .plugin(
                file: dir.appendingPathComponent("plugin/pet.js"),
                alternates: [dir.appendingPathComponent("plugins/pet.js")],
                source: OpencodePlugin.source),
            commandFiles: AgentCommands.files(
                folder: "command", args: "$ARGUMENTS", style: .frontmatter))
    }

    /// pi has no command hooks; it loads TypeScript extensions from
    /// ~/.pi/agent/extensions. Needs pi 0.83 or later, where the extension
    /// event bus became public.
    static var pi: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent")
        return HookHost(
            id: "pi", name: "pi", fileName: "pet.ts",
            kind: .plugin(
                file: dir.appendingPathComponent("extensions/pet.ts"),
                alternates: [],
                source: PiPlugin.source))
    }

    static var all: [HookHost] {
        [.claude, .codex, .gemini, .opencode, .antigravity, .cursor, .pi]
    }
    static func named(_ id: String) -> HookHost? { all.first { $0.id == id } }
}
