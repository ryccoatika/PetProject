//  CLI+App.swift
//  Desktop Pet
//
//  Commands that drive the running app.

import Cocoa

extension CLI {

    // MARK: app

    static func status() {
        Prefs.refresh()
        let d = Prefs.store
        let live = (try? String(contentsOf: SkinStore.configDir.appendingPathComponent("runtime"),
                                encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRunning = !running.isEmpty
        print("app        : \(isRunning ? "running" : "not running")")
        if isRunning, let live { print("             \(live)") }
        if let live, live.contains("cli=needs-path") {
            print("             ! `pet` is installed but your shell cannot find it —")
            print("               see Command Line Tool in the menu bar")
        }
        print("config     : \(tilde(SkinStore.configDir))\(SkinStore.configDirIsFromEnvironment ? "  ($PET_CONFIG_DIR)" : SkinStore.isCustomConfigDir ? "  (custom)" : "")")
        let skins = SkinStore.load().skins
        print("skins      : \(skins.count) in \(tilde(SkinStore.userDir))")
        print("current    : \(d.string(forKey: "petSkin") ?? "tabby")")
        print("hidden     : \(d.bool(forKey: "petHidden") ? "yes" : "no")")
        print("chase      : \(d.bool(forKey: "petChase") ? "on" : "off")")
        print("menu bar   : \(d.bool(forKey: "petTrayHidden") ? "hidden" : "shown")")

        let state = SkinStore.configDir.appendingPathComponent("state")
        if let raw = try? String(contentsOf: state, encoding: .utf8) {
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
            if parts.count >= 3, let ts = Double(parts[2]) {
                let age = Int(Date().timeIntervalSince1970 - ts)
                let tool = parts[1].isEmpty ? "" : " (\(parts[1]))"
                print("last event : \(parts[0])\(tool), \(age)s ago")
            }
        } else {
            print("last event : none — run `pet plugin install` to react to Claude Code")
        }
    }

    static func start() {
        guard let app = appURL else { fail("Pet.app not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [app.path]
        try? p.run()
        p.waitUntilExit()
        print("started \(tilde(app))")
    }

    static func stop() {
        let apps = running
        guard !apps.isEmpty else { print("not running"); return }
        apps.forEach { $0.terminate() }
        print("stopped")
    }

    static func tray(_ action: String?) {
        Prefs.refresh()
        switch action {
        case "show", "hide":
            let hide = action == "hide"
            Prefs.store.set(hide, forKey: "petTrayHidden")
            Prefs.store.synchronize()
            Prefs.notifyRunningApp()
            print(hide ? "menu bar icon hidden — `pet tray show` brings it back"
                       : "menu bar icon shown")
        case nil, "status":
            print(Prefs.store.bool(forKey: "petTrayHidden") ? "hidden" : "shown")
        default:
            fail("usage: pet tray [show | hide]")
        }
    }

    static func setHidden(_ value: Bool) {
        Prefs.store.set(value, forKey: "petHidden")
        Prefs.store.synchronize()
        Prefs.notifyRunningApp()
        print(value ? "pet hidden" : "pet shown")
    }
}
