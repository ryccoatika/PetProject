//  AppDelegate+Menu.swift
//  Desktop Pet
//
//  Building the menu bar and keeping it current.

import Cocoa

extension AppDelegate {

    // MARK: menu

    /// Built once. Titles and check-marks are refreshed in menuNeedsUpdate,
    /// so they are always current when the menu opens.
    func buildMenu() {
        mainMenu.removeAllItems()
        mainMenu.delegate = self

        statusRow = NSMenuItem(title: statusSummary(), action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        mainMenu.addItem(statusRow)
        mainMenu.addItem(.separator())

        visItem = NSMenuItem(title: hidden ? "Show Pet" : "Hide Pet",
                             action: #selector(toggleHidden), keyEquivalent: "h")
        visItem.target = self
        mainMenu.addItem(visItem)

        let trayItem = NSMenuItem(title: "Hide Menu Bar Icon",
                                  action: #selector(hideTray), keyEquivalent: "")
        trayItem.target = self
        mainMenu.addItem(trayItem)
        mainMenu.addItem(.separator())

        let skinItem = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
        skinMenu.delegate = self          // repopulated from disk each time it opens
        populateSkinMenu()
        skinItem.submenu = skinMenu
        mainMenu.addItem(skinItem)

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeMenu.autoenablesItems = false
        buildSizeMenu()
        sizeItem.submenu = sizeMenu
        mainMenu.addItem(sizeItem)

        let pluginItem = NSMenuItem(title: "Agent Plugin", action: nil, keyEquivalent: "")
        pluginMenu.delegate = self         // re-read from disk each time it opens
        pluginMenu.autoenablesItems = false
        populatePluginMenu()
        pluginItem.submenu = pluginMenu
        mainMenu.addItem(pluginItem)
        mainMenu.addItem(.separator())

        chaseItem = NSMenuItem(title: "Chase cursor when idle",
                               action: #selector(toggleChase), keyEquivalent: "")
        chaseItem.target = self
        chaseItem.state = chaseWhenIdle ? .on : .off
        mainMenu.addItem(chaseItem)

        let hint = NSMenuItem(title: "Drag to move · double-click to toggle chase",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        mainMenu.addItem(hint)
        mainMenu.addItem(.separator())

        if !cliReachable {
            let cli = NSMenuItem(title: "Command Line Tool — needs PATH setup",
                                 action: #selector(showCommandLineInfo), keyEquivalent: "")
            cli.target = self
            if let warning = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                     accessibilityDescription: "warning") {
                let amber = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
                cli.image = warning.withSymbolConfiguration(amber)
            }
            cliItem = cli
            mainMenu.addItem(cli)
            mainMenu.addItem(.separator())
        } else {
            cliItem = nil
        }

        let quit = NSMenuItem(title: "Quit Pet", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        mainMenu.addItem(quit)

        statusItem?.menu = mainMenu
    }

    /// Cheap: only the values that change while the app runs.
    /// A slider lives in the menu as a custom view; the readout above it is
    /// updated as it moves rather than being rebuilt, so dragging stays smooth.
    func buildSizeMenu() {
        sizeMenu.removeAllItems()

        let readout = NSMenuItem(title: sizeLabel(), action: nil, keyEquivalent: "")
        readout.isEnabled = false
        sizeReadout = readout
        sizeMenu.addItem(readout)

        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        let slider = NSSlider(frame: NSRect(x: 18, y: 5, width: 184, height: 20))
        slider.minValue = Double(AppDelegate.scaleRange.lowerBound)
        slider.maxValue = Double(AppDelegate.scaleRange.upperBound)
        slider.doubleValue = Double(artScale)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sizeSliderMoved(_:))
        holder.addSubview(slider)
        sizeSlider = slider

        let row = NSMenuItem()
        row.view = holder
        sizeMenu.addItem(row)

        sizeMenu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset to 100%", action: #selector(resetSize),
                               keyEquivalent: "")
        reset.target = self
        reset.isEnabled = artScale != 1
        sizeResetItem = reset
        sizeMenu.addItem(reset)
    }

    func sizeLabel() -> String { "Size: \(Int((artScale * 100).rounded()))%" }

    @objc func sizeSliderMoved(_ sender: NSSlider) {
        setArtScale(CGFloat(sender.doubleValue))
        sizeReadout?.title = sizeLabel()
        // the menu is still open, so this item was built before the drag
        sizeResetItem?.isEnabled = artScale != 1
    }

    @objc func resetSize() {
        setArtScale(1)
        sizeSlider?.doubleValue = 1
        sizeReadout?.title = sizeLabel()
        sizeResetItem?.isEnabled = false
    }

    func refreshMenu() {
        statusRow?.title = statusSummary()
        visItem?.title = hidden ? "Show Pet" : "Hide Pet"
        chaseItem?.state = chaseWhenIdle ? .on : .off
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === mainMenu { refreshMenu() }
        if menu === skinMenu {
            reloadSkins()
            populateSkinMenu()
        }
        if menu === pluginMenu { populatePluginMenu() }
        if menu === sizeMenu { buildSizeMenu() }
    }

    func statusSummary() -> String {
        if hidden { return "Hidden — \(liveSummary().lowercased())" }
        return liveSummary()
    }

    func liveSummary() -> String {
        switch view.pose {
        case .working:   return "Working — \(lastTool.isEmpty ? "tool" : lastTool)"
        case .thinking:  return "Claude is thinking"
        case .alert:     return "Waiting for you"
        case .failed:    return "A tool failed"
        case .celebrate: return "Just finished"
        case .sleeping:  return "Asleep"
        default:         return "Idle"
        }
    }

    func reloadSkins() {
        let result = SkinStore.load()
        skins = result.skins
        skinErrors = result.errors
        sprites = SpriteStore.load()
        // keep showing the current skin if its file is still there, else fall back
        view.skin = skins.first { $0.id == view.skin.id } ?? skins[0]
    }

    /// Rebuilt on every open so skins added to the folder appear without a restart.
    func populateSkinMenu() {
        skinMenu.removeAllItems()
        let currentID = view.sprite?.id ?? view.skin.id
        for (i, sk) in skins.enumerated() {
            let it = NSMenuItem(title: sk.name, action: #selector(setSkin(_:)), keyEquivalent: "")
            it.target = self; it.tag = i
            it.state = sk.id == currentID ? .on : .off
            skinMenu.addItem(it)
        }
        if !sprites.isEmpty {
            skinMenu.addItem(.separator())
            for (i, pet) in sprites.enumerated() {
                let it = NSMenuItem(title: pet.name, action: #selector(setSpritePet(_:)),
                                    keyEquivalent: "")
                it.target = self; it.tag = i
                it.state = pet.id == currentID ? .on : .off
                // alt-click removes an installed pet
                let alt = NSMenuItem(title: "Remove \(pet.name)",
                                     action: #selector(removeSpritePet(_:)), keyEquivalent: "")
                alt.target = self; alt.tag = i
                alt.isAlternate = true
                alt.keyEquivalentModifierMask = .option
                skinMenu.addItem(it)
                skinMenu.addItem(alt)
            }
        }
        for err in skinErrors {
            let it = NSMenuItem(title: "⚠ \(err)", action: nil, keyEquivalent: "")
            it.isEnabled = false
            skinMenu.addItem(it)
        }
        skinMenu.addItem(.separator())
        for (title, sel) in [("Install Skin from codex-pets.net…", #selector(installSpritePet)),
                             ("Browse codex-pets.net", #selector(browseSpritePets)),
                             ("Import Skin…", #selector(importSkin)),
                             ("Export Current Skin…", #selector(exportSkin))] {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            skinMenu.addItem(it)
        }

        skinMenu.addItem(.separator())
        let where_ = NSMenuItem(title: "Config: \(Self.tildePath(SkinStore.configDir))",
                                action: nil, keyEquivalent: "")
        where_.isEnabled = false
        skinMenu.addItem(where_)

        var tail: [(String, Selector)] = [("Open Config Folder", #selector(openSkinsFolder)),
                                          ("Change Config Folder…", #selector(changeConfigFolder))]
        if SkinStore.isCustomConfigDir && !SkinStore.configDirIsFromEnvironment {
            tail.append(("Use Default Location", #selector(useDefaultConfigFolder)))
        }
        tail.append(("Reload Skins", #selector(reloadSkinsMenu)))
        for (title, sel) in tail {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            if title == "Change Config Folder…" && SkinStore.configDirIsFromEnvironment {
                it.action = nil                     // $PET_CONFIG_DIR wins; nothing to change
                it.isEnabled = false
                it.title = "Set by $PET_CONFIG_DIR"
            }
            skinMenu.addItem(it)
        }
    }

    /// ~/-relative path, so the menu line stays short.
    static func tildePath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    func populatePluginMenu() {
        pluginMenu.removeAllItems()
        for (i, host) in HookHost.all.enumerated() {
            let registered = HookPlugin.isRegistered(host)
            let title = host.isPresent || registered ? host.name : "\(host.name) — not installed"
            let it = NSMenuItem(title: title, action: #selector(togglePlugin(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = registered ? .on : .off
            it.isEnabled = host.isPresent || registered
            pluginMenu.addItem(it)
        }

        pluginMenu.addItem(.separator())
        let hint = NSMenuItem(title: "Tick an agent to let it drive the pet",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        pluginMenu.addItem(hint)

        // a folder we manage that an older install left hooks in
        let managed = Set(HookHost.claude.files.map {
            $0.deletingLastPathComponent().standardizedFileURL.path
        })
        for dir in HookHost.otherClaudeDirs(besides: managed)
        where HookPlugin.registeredCount(in: dir.appendingPathComponent("settings.json")) > 0 {
            let it = NSMenuItem(title: "Also in \(CLI.tilde(dir)) — remove",
                                action: #selector(removeStrayPlugin(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = dir
            pluginMenu.addItem(it)
        }
    }
}
