//  AppDelegate+Tools.swift
//  Desktop Pet
//
//  The `pet` command line tool, the menu bar icon, and visibility.

import Cocoa

extension AppDelegate {

    /// called `pet` is left alone.
    func installCommandLineTool() {
        let fm = FileManager.default
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath(),
              exe.lastPathComponent == "Pet" else { return }

        var target: String?
        for dir in ["/usr/local/bin", NSHomeDirectory() + "/.local/bin"] {
            let link = dir + "/pet"
            if let dest = try? fm.destinationOfSymbolicLink(atPath: link) {
                if dest == exe.path { return }                  // already correct
                if dest.contains("/Pet.app/Contents/MacOS/") {  // an older install
                    try? fm.removeItem(atPath: link)
                    try? fm.createSymbolicLink(atPath: link, withDestinationPath: exe.path)
                    return
                }
                return                                          // someone else's `pet`
            }
            if fm.fileExists(atPath: link) { return }
            if target == nil, fm.isWritableFile(atPath: dir) { target = dir }
        }

        let dir = target ?? NSHomeDirectory() + "/.local/bin"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: dir + "/pet", withDestinationPath: exe.path)
        Prefs.store.set(dir + "/pet", forKey: "petCLIPath")
    }

    /// Ask the user's login shell whether `pet` is on its PATH. The app's own
    /// environment cannot answer this: launched from Finder it never sees the
    /// shell's profile, and a folder missing from /etc/paths may still be
    /// added by the user's own .zshrc.
    func checkCommandLineReachable() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: shell)
            probe.arguments = ["-ilc", "command -v pet"]
            let pipe = Pipe()
            probe.standardOutput = pipe
            probe.standardError = FileHandle.nullDevice
            guard (try? probe.run()) != nil else { return }
            // a broken profile must not leave the probe hanging around
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if probe.isRunning { probe.terminate() }
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            probe.waitUntilExit()
            let found = probe.terminationStatus == 0 && output.contains("/pet")
            DispatchQueue.main.async {
                guard let self, found != self.cliReachable else { return }
                self.cliReachable = found
                self.writeRuntime()
                self.buildMenu()               // the warning appears or goes away
            }
        }
    }

    /// Where the `pet` command ended up, if we put it somewhere.
    var cliPath: String? {
        for dir in ["/usr/local/bin", NSHomeDirectory() + "/.local/bin"] {
            if FileManager.default.fileExists(atPath: dir + "/pet") { return dir + "/pet" }
        }
        return nil
    }

    /// The system default PATH, so we can tell whether `pet` will be found.
    /// The app's own PATH is useless here: a Finder-launched app does not get
    /// the user's shell environment.
    var cliOnDefaultPath: Bool {
        guard let path = cliPath else { return false }
        let dir = (path as NSString).deletingLastPathComponent
        let system = (try? String(contentsOfFile: "/etc/paths", encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        return system.contains(dir)
    }

    @objc func showCommandLineInfo() {
        checkCommandLineReachable()          // it may have been fixed since
        let alert = NSAlert()
        guard let path = cliPath else {
            alert.messageText = "The pet command is not installed"
            alert.informativeText = "Reopening the app usually installs it. It normally goes to "
                                  + "/usr/local/bin, or ~/.local/bin when that is not writable."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let dir = (path as NSString).deletingLastPathComponent
        let line = "export PATH=\"\(dir.replacingOccurrences(of: NSHomeDirectory(), with: "$HOME")):$PATH\""
        alert.messageText = "The pet command is installed"
        if cliOnDefaultPath {
            alert.informativeText = "It is at \(CLI.tilde(URL(fileURLWithPath: path))) and should "
                                  + "work in any terminal.\n\nTry:  pet help"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        alert.informativeText = "It is at \(CLI.tilde(URL(fileURLWithPath: path))), but that folder "
                              + "is not on the default PATH, so your shell may not find it.\n\n"
                              + "Add this line to your shell profile "
                              + "(~/.zshrc):\n\n    \(line)\n\n"
                              + "Until then the full path works:  \(path) help"
        alert.addButton(withTitle: "Copy the line")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(line, forType: .string)
        }
    }

    func showTray() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐈"
        statusItem = item
        buildMenu()
    }

    func removeTray() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    @objc func hideTray() {
        trayHidden = true
        Prefs.store.set(true, forKey: "petTrayHidden")
        removeTray()
        writeRuntime()
        // This menu was the only way back, so say how to return.
        let alert = NSAlert()
        alert.messageText = "Menu bar icon hidden"
        alert.informativeText = "The pet keeps running. To bring the icon back, "
                              + "run this in Terminal:\n\n    pet tray show"
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func toggleHidden() {
        hidden.toggle()
        Prefs.store.set(hidden, forKey: "petHidden")
        if hidden {
            window.orderOut(nil)
        } else {
            place()
            window.orderFrontRegardless()
        }
        writeRuntime()
        refreshMenu()
    }

    @objc func toggleChase() {
        chaseWhenIdle.toggle()
        Prefs.store.set(chaseWhenIdle, forKey: "petChase")
        flashText = chaseWhenIdle ? "chase on" : "chase off"
        flashUntil = Date().addingTimeInterval(1.6)
        refreshMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }

    /// What the running app is actually doing, for `pet status`.
    /// Rebuild the timer at a new rate. Tolerance lets the system coalesce
}
