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
        let live =
            (try? String(
                contentsOf: SkinStore.configDir.appendingPathComponent("runtime"),
                encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRunning = !running.isEmpty
        print("app        : \(isRunning ? "running" : "not running")")
        if isRunning, let live { print("             \(live)") }
        if let live, live.contains("cli=needs-path") {
            print("             ! `pet` is installed but your shell cannot find it —")
            print("               see Command Line Tool in the menu bar")
        }
        print(
            "config     : \(tilde(SkinStore.configDir))\(SkinStore.configDirIsFromEnvironment ? "  ($PET_CONFIG_DIR)" : SkinStore.isCustomConfigDir ? "  (custom)" : "")"
        )
        let skins = SkinStore.load().skins
        print("skins      : \(skins.count) in \(tilde(SkinStore.userDir))")
        print("current    : \(d.string(forKey: "petSkin") ?? "tabby")")
        print("hidden     : \(d.bool(forKey: "petHidden") ? "yes" : "no")")
        print("chase      : \(d.bool(forKey: "petChase") ? "on" : "off")")
        print("antics     : \(d.bool(forKey: "petAnticsOff") ? "off" : "on")")
        print("menu bar   : \(d.bool(forKey: "petTrayHidden") ? "hidden" : "shown")")
        print("bubbles    : \(d.bool(forKey: "petBubblesHidden") ? "hidden" : "shown")")
        print("usage badge: \(d.bool(forKey: "petUsageHidden") ? "hidden" : "shown")")
        print(
            "size       : \(Int((((d.object(forKey: "petScale") as? Double) ?? 1) * 100).rounded()))%"
        )

        let state = SkinStore.configDir.appendingPathComponent("state")
        if let raw = try? String(contentsOf: state, encoding: .utf8) {
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(
                separatedBy: "|")
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
            print(
                hide
                    ? "menu bar icon hidden — `pet tray show` brings it back"
                    : "menu bar icon shown")
        case nil, "status":
            print(Prefs.store.bool(forKey: "petTrayHidden") ? "hidden" : "shown")
        default:
            fail("usage: pet tray [show | hide]")
        }
    }

    /// `pet stats` — a small tally of today and the recent past.
    static func stats() {
        let (today, totals) = Stats.summary()
        print("today:")
        print("  sessions : \(today.sessions)")
        print("  tools    : \(today.tools)")
        print("  failures : \(today.failures)")
        print("  active   : \(Stats.humanSpan(today.activeSeconds))")
        print("")
        print("last \(totals.days) day(s):")
        print("  sessions : \(totals.sessions)")
        print("  tools    : \(totals.tools)")
        print("  failures : \(totals.failures)")
    }

    /// Idle antics: the bored pet wandering, waving or sulking on its own.
    static func antics(_ action: String?) {
        Prefs.refresh()
        switch action {
        case "on", "off":
            Prefs.store.set(action == "off", forKey: "petAnticsOff")
            Prefs.store.synchronize()
            Prefs.notifyRunningApp()
            print(action == "off" ? "idle antics off" : "idle antics on")
        case nil, "status":
            print(Prefs.store.bool(forKey: "petAnticsOff") ? "off" : "on")
        default:
            fail("usage: pet antics [on | off]")
        }
    }

    /// The activity bubbles above the pet's head.
    static func bubbles(_ action: String?) {
        Prefs.refresh()
        switch action {
        case "show", "hide":
            Prefs.store.set(action == "hide", forKey: "petBubblesHidden")
            Prefs.store.synchronize()
            Prefs.notifyRunningApp()
            print(action == "hide" ? "activity bubbles hidden" : "activity bubbles shown")
        case nil, "status":
            print(Prefs.store.bool(forKey: "petBubblesHidden") ? "hidden" : "shown")
        default:
            fail("usage: pet bubbles [show | hide]")
        }
    }

    /// `pet size` prints it, `pet size 150` sets it, `pet size reset` clears it.
    static func size(_ argument: String?) {
        Prefs.refresh()
        let current = (Prefs.store.object(forKey: "petScale") as? Double) ?? 1

        guard let argument else {
            print("\(Int((current * 100).rounded()))%")
            return
        }
        if argument == "reset" || argument == "default" {
            Prefs.store.removeObject(forKey: "petScale")
            Prefs.store.synchronize()
            Prefs.notifyRunningApp()
            print("size reset to 100%")
            return
        }
        let text = argument.hasSuffix("%") ? String(argument.dropLast()) : argument
        guard let number = Double(text), number > 0 else {
            fail("usage: pet size [50…200 | reset]")
        }
        // accept either a percentage or a plain multiplier
        let scale = number > 5 ? number / 100 : number
        guard scale >= 0.5, scale <= 2 else {
            fail("size must be between 50% and 200%")
        }
        Prefs.store.set(scale, forKey: "petScale")
        Prefs.store.synchronize()
        Prefs.notifyRunningApp()
        print("size set to \(Int((scale * 100).rounded()))%")
    }

    static func setHidden(_ value: Bool) {
        Prefs.store.set(value, forKey: "petHidden")
        Prefs.store.synchronize()
        Prefs.notifyRunningApp()
        print(value ? "pet hidden" : "pet shown")
    }
}
