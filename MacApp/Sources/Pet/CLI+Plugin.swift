//  CLI+Plugin.swift
//  Desktop Pet
//
//  Commands for the agent plugins, and uninstalling the app.

import Cocoa

extension CLI {

    // MARK: plugin

    /// `pet plugin install [claude|codex] [--path <dir>]…`
    /// With no agent, every agent that is actually installed for this user.
    /// With no --path, each agent's default config folder.
    static func hosts(_ args: [String]) -> [HookHost] {
        var paths: [URL] = []
        var agent: String?
        var rest = Array(args.dropFirst())  // drop install/uninstall
        while let arg = rest.first {
            rest.removeFirst()
            if arg == "--path" || arg == "-p" {
                guard let value = rest.first else { fail("--path needs a folder") }
                rest.removeFirst()
                paths.append(SkinStore.expand(value).standardizedFileURL)
            } else if arg.hasPrefix("--path=") {
                paths.append(SkinStore.expand(String(arg.dropFirst(7))).standardizedFileURL)
            } else if arg.hasPrefix("-") {
                fail("unknown option \"\(arg)\"")
            } else if agent == nil {
                agent = arg.lowercased()
            } else {
                fail("unexpected argument \"\(arg)\"")
            }
        }

        var chosen: [HookHost]
        if let agent {
            guard let host = HookHost.named(agent) else {
                fail("unknown agent \"\(agent)\" — use claude or codex")
            }
            chosen = [host]
        } else {
            guard paths.isEmpty else {
                fail("--path needs an agent, e.g. pet plugin install claude --path <dir>")
            }
            chosen = HookHost.all.filter(\.isPresent)
            if chosen.isEmpty {
                fail("no supported agent found (looked for ~/.claude and ~/.codex)")
            }
        }
        return paths.isEmpty ? chosen : chosen.map { $0.targeting(paths) }
    }

    static func plugin(_ args: [String]) {
        switch args.first {
        case "install":
            let chosen = hosts(args)
            print("Installing the pet plugin for \(chosen.map(\.name).joined(separator: " and "))…")
            HookPlugin.install(chosen)
        case "uninstall":
            let chosen = args.count > 1 ? hosts(args) : HookHost.all
            print("Removing the pet plugin…")
            HookPlugin.uninstall(chosen)
        case "status":
            HookPlugin.status()
        default:
            fail("usage: pet plugin [install | uninstall | status] [claude | codex] [--path <dir>]")
        }
    }

    // MARK: uninstall

    static func uninstall(all: Bool) {
        running.forEach { $0.terminate() }
        if HookPlugin.isRegisteredAnywhere {
            print("Removing the pet plugin…")
            HookPlugin.uninstall(HookHost.all)
        }
        if let app = appURL {
            try? FileManager.default.removeItem(at: app)
            print("  ✓  removed \(tilde(app))")
        }
        for dir in ["/usr/local/bin", "\(NSHomeDirectory())/.local/bin"] {
            let link = URL(fileURLWithPath: dir).appendingPathComponent("pet")
            if FileManager.default.fileExists(atPath: link.path) {
                try? FileManager.default.removeItem(at: link)
                print("  ✓  removed \(tilde(link))")
            }
        }
        if all {
            try? FileManager.default.removeItem(at: SkinStore.configDir)
            print("  ✓  removed \(tilde(SkinStore.configDir)) (skins and settings)")
        } else {
            print("")
            print("Your skins in \(tilde(SkinStore.userDir)) were left in place.")
        }
    }
}
