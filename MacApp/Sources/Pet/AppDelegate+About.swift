//  AppDelegate+About.swift
//  Desktop Pet
//
//  The About window. A real window rather than the standard panel or an
//  alert: Check for Updates lives here, its title saying "Checking…" while
//  it asks GitHub, and shows its answer as a sheet — About stays open
//  throughout. The config folder and the log file are surfaced here too,
//  so a bug report and a skin folder are both one click away.

import Cocoa

extension AppDelegate {

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = aboutWindow {
            aboutConfigLabel?.stringValue = Self.aboutConfigLine()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "Desktop Pet")
        title.font = .boldSystemFont(ofSize: 15)

        let version = NSTextField(labelWithString: "Version \(Build.version)")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor

        let currentArt = view.sprite.map { "\($0.name) — \($0.rows) row atlas" } ?? view.skin.name
        let agents = HookHost.all.filter { HookPlugin.isRegistered($0) }.map(\.name)
        let info = NSTextField(
            wrappingLabelWithString:
                "A desktop pet that reacts to your coding agent.\n"
                + "Drawn in code — no image assets.\n\n"
                + "Currently wearing \(currentArt).\n"
                + (agents.isEmpty
                    ? "No agent is driving it yet."
                    : "Driven by \(agents.joined(separator: ", ")).")
                + (Stats.aboutLine().map { "\n\n\($0)" } ?? "")
        )
        info.font = .systemFont(ofSize: 11)
        info.alignment = .center
        info.preferredMaxLayoutWidth = 280

        let config = NSTextField(labelWithString: Self.aboutConfigLine())
        config.font = .systemFont(ofSize: 10)
        config.textColor = .secondaryLabelColor
        config.lineBreakMode = .byTruncatingMiddle
        aboutConfigLabel = config

        // The buttons, as a vertical list of equal width.
        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.widthAnchor.constraint(equalToConstant: 230).isActive = true
            return b
        }
        // No spinner: while a check or an install runs the button disables
        // and its title says so.
        let check = button("Check for Updates", #selector(checkForUpdates))
        aboutCheckButton = check

        var rows: [NSView] = [
            check,
            button("Show Log File in Finder", #selector(revealLogFile)),
            button("Open Config Folder", #selector(openSkinsFolder)),
        ]
        if SkinStore.configDirIsFromEnvironment {
            let fixed = button("Set by $PET_CONFIG_DIR", #selector(showAbout))
            fixed.isEnabled = false
            rows.append(fixed)
        } else {
            rows.append(button("Change Config Folder…", #selector(changeConfigFolder)))
            if SkinStore.isCustomConfigDir {
                rows.append(button("Use Default Location", #selector(useDefaultConfigFolder)))
            }
        }
        rows.append(button("GitHub", #selector(openGitHubPage)))

        let buttons = NSStackView(views: rows)
        buttons.orientation = .vertical
        buttons.alignment = .centerX
        buttons.spacing = 6

        let stack = NSStackView(views: [icon, title, version, info, config, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 24, bottom: 18, right: 24)

        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "About Desktop Pet"
        window.isReleasedWhenClosed = false  // kept and reused
        window.contentView = stack
        stack.layoutSubtreeIfNeeded()
        window.setContentSize(stack.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    static func aboutConfigLine() -> String {
        var line = "Config: \(tildePath(SkinStore.configDir))"
        if SkinStore.configDirIsFromEnvironment { line += "  ($PET_CONFIG_DIR)" }
        return line
    }

    /// Reveal the log in Finder, selected — the file a bug report should
    /// come with. A never-written log still gets its folder shown.
    @objc func revealLogFile() {
        if FileManager.default.fileExists(atPath: Log.file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([Log.file])
        } else {
            Log.info("log opened from About")  // ensures there is a file to show
            try? FileManager.default.createDirectory(
                at: Log.folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Log.folder)
        }
    }

    @objc func openGitHubPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ryccoatika/PetProject")!)
    }
}
