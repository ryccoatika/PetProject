//  AppDelegate+About.swift
//  Desktop Pet
//
//  The About window. A real window rather than the standard panel or an
//  alert: Check for Updates lives here, spins in place while it asks
//  GitHub, and shows its answer as a sheet — About stays open throughout.

import Cocoa

extension AppDelegate {

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = aboutWindow {
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

        let github = NSButton(
            title: "GitHub", target: self, action: #selector(openGitHubPage))
        let check = NSButton(
            title: "Check for Updates", target: self, action: #selector(checkForUpdates))
        aboutCheckButton = check

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        aboutSpinner = spinner

        let buttons = NSStackView(views: [github, check, spinner])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [icon, title, version, info, buttons])
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

    @objc func openGitHubPage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ryccoatika/PetProject")!)
    }
}
