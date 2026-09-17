//  AppDelegate+Menu.swift
//  Desktop Pet
//
//  Building the menu bar and keeping it current.

import Cocoa

extension AppDelegate {

    // MARK: menu

    /// A template SF Symbol for a menu row, so the icons follow the menu's
    /// light or dark appearance.
    func menuSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// Built once. Titles and check-marks are refreshed in menuNeedsUpdate,
    /// so they are always current when the menu opens.
    ///
    /// Three groups keep the top level short: what the pet is doing, then
    /// Appearance (how it looks), Behaviour (what it does) and Agent Plugin
    /// (which agents drive it), then the app rows.
    func buildMenu() {
        mainMenu.removeAllItems()
        mainMenu.delegate = self

        statusRow = NSMenuItem(title: statusSummary(), action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        mainMenu.addItem(statusRow)
        if let tag = updateAvailable {
            let update = NSMenuItem(
                title: "Update available — \(tag)",
                action: #selector(openReleasesPage), keyEquivalent: "")
            update.target = self
            update.image = menuSymbol("arrow.down.circle")
            mainMenu.addItem(update)
        }
        mainMenu.addItem(.separator())

        visItem = NSMenuItem(
            title: hidden ? "Show Pet" : "Hide Pet",
            action: #selector(toggleHidden), keyEquivalent: "h")
        visItem.target = self
        visItem.image = menuSymbol(hidden ? "eye" : "eye.slash")
        mainMenu.addItem(visItem)
        mainMenu.addItem(.separator())

        // Appearance — how the pet looks
        buildAppearanceMenu()
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearanceItem.image = menuSymbol("paintpalette")
        appearanceItem.submenu = appearanceMenu
        mainMenu.addItem(appearanceItem)

        // Behaviour — what the pet does
        buildBehaviorMenu()
        let behaviorItem = NSMenuItem(title: "Behaviour", action: nil, keyEquivalent: "")
        behaviorItem.image = menuSymbol("slider.horizontal.3")
        behaviorItem.submenu = behaviorMenu
        mainMenu.addItem(behaviorItem)

        let pluginItem = NSMenuItem(title: "Agent Plugin", action: nil, keyEquivalent: "")
        pluginMenu.delegate = self  // re-read from disk each time it opens
        pluginMenu.autoenablesItems = false
        populatePluginMenu()
        pluginItem.image = menuSymbol("bolt.horizontal")
        pluginItem.submenu = pluginMenu
        mainMenu.addItem(pluginItem)
        mainMenu.addItem(.separator())

        if !cliReachable {
            let cli = NSMenuItem(
                title: "Command Line Tool — needs PATH setup",
                action: #selector(showCommandLineInfo), keyEquivalent: "")
            cli.target = self
            if let warning = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "warning")
            {
                let amber = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
                cli.image = warning.withSymbolConfiguration(amber)
            }
            cliItem = cli
            mainMenu.addItem(cli)
            mainMenu.addItem(.separator())
        } else {
            cliItem = nil
        }

        let about = NSMenuItem(
            title: "About Desktop Pet", action: #selector(showAbout),
            keyEquivalent: "")
        about.target = self
        about.image = menuSymbol("info.circle")
        mainMenu.addItem(about)

        let quit = NSMenuItem(title: "Quit Pet", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        mainMenu.addItem(quit)

        statusItem?.menu = mainMenu
    }

    /// Appearance: skin, size and the menu bar icon.
    func buildAppearanceMenu() {
        appearanceMenu.removeAllItems()
        appearanceMenu.autoenablesItems = false

        let skinItem = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
        skinMenu.delegate = self  // repopulated from disk each time it opens
        populateSkinMenu()
        skinItem.image = menuSymbol("pawprint")
        skinItem.submenu = skinMenu
        appearanceMenu.addItem(skinItem)

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeMenu.autoenablesItems = false
        buildSizeMenu()
        sizeItem.image = menuSymbol("arrow.up.left.and.arrow.down.right")
        sizeItem.submenu = sizeMenu
        appearanceMenu.addItem(sizeItem)

        let iconItem = NSMenuItem(title: "Menu Bar Icon", action: nil, keyEquivalent: "")
        iconMenu.delegate = self  // ticks refresh each time it opens
        iconMenu.autoenablesItems = false
        populateIconMenu()
        iconItem.image = menuSymbol("menubar.rectangle")
        iconItem.submenu = iconMenu
        appearanceMenu.addItem(iconItem)
    }

    /// Behaviour: the toggles and Follow Session.
    func buildBehaviorMenu() {
        behaviorMenu.removeAllItems()
        behaviorMenu.autoenablesItems = false
        behaviorMenu.delegate = self  // refresh the checkmarks on open

        chaseItem = NSMenuItem(
            title: "Chase cursor when idle",
            action: #selector(toggleChase), keyEquivalent: "")
        chaseItem.target = self
        chaseItem.state = chaseWhenIdle ? .on : .off
        chaseItem.image = menuSymbol("cursorarrow.motionlines")
        behaviorMenu.addItem(chaseItem)

        anticsItem = NSMenuItem(
            title: "Antics When Bored",
            action: #selector(toggleAntics), keyEquivalent: "")
        anticsItem.target = self
        anticsItem.state = anticsEnabled ? .on : .off
        anticsItem.image = menuSymbol("figure.wave")
        behaviorMenu.addItem(anticsItem)

        bubbleItem = NSMenuItem(
            title: "Show Activity Bubbles",
            action: #selector(toggleBubbles), keyEquivalent: "")
        bubbleItem.target = self
        bubbleItem.state = bubblesEnabled ? .on : .off
        bubbleItem.image = menuSymbol("bubble.left")
        behaviorMenu.addItem(bubbleItem)

        chimeItem = NSMenuItem(
            title: "Chime When an Agent Needs You",
            action: #selector(toggleChime), keyEquivalent: "")
        chimeItem.target = self
        chimeItem.state = chimeEnabled ? .on : .off
        chimeItem.image = menuSymbol("bell")
        behaviorMenu.addItem(chimeItem)

        behaviorMenu.addItem(.separator())

        let followItem = NSMenuItem(title: "Follow Session", action: nil, keyEquivalent: "")
        followMenu.delegate = self  // rebuilt from the live sessions each open
        followMenu.autoenablesItems = false
        populateFollowMenu()
        followItem.image = menuSymbol("dot.viewfinder")
        followItem.submenu = followMenu
        behaviorMenu.addItem(followItem)

        behaviorMenu.addItem(.separator())
        let hint = NSMenuItem(
            title: "Drag to move · double-click to chase · flick to throw · right-click for toggles",
            action: nil, keyEquivalent: "")
        hint.isEnabled = false
        behaviorMenu.addItem(hint)
    }

    /// Cheap: only the values that change while the app runs.
    /// A slider lives in the menu as a custom view; the readout above it is
    /// updated as it moves rather than being rebuilt, so dragging stays smooth.
    func buildSizeMenu() {
        sizeMenu.removeAllItems()

        // A custom view rather than a disabled item, so the readout keeps a
        // full-contrast label colour instead of the greyed disabled look.
        let labelHolder = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        let label = NSTextField(labelWithString: sizeLabel())
        label.frame = NSRect(x: 20, y: 2, width: 184, height: 16)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        labelHolder.addSubview(label)
        sizeReadout = label
        let readout = NSMenuItem()
        readout.view = labelHolder
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
        let reset = NSMenuItem(
            title: "Reset to 100%", action: #selector(resetSize),
            keyEquivalent: "")
        reset.target = self
        reset.isEnabled = artScale != 1
        sizeResetItem = reset
        sizeMenu.addItem(reset)
    }

    func sizeLabel() -> String { "Size: \(Int((artScale * 100).rounded()))%" }

    @objc func sizeSliderMoved(_ sender: NSSlider) {
        setArtScale(CGFloat(sender.doubleValue))
        sizeReadout?.stringValue = sizeLabel()
        // the menu is still open, so this item was built before the drag
        sizeResetItem?.isEnabled = artScale != 1
    }

    @objc func resetSize() {
        setArtScale(1)
        sizeSlider?.doubleValue = 1
        sizeReadout?.stringValue = sizeLabel()
        sizeResetItem?.isEnabled = false
    }

    /// The right-click menu on the pet itself: the Behaviour toggles without
    /// a trip to the menu bar. Built fresh each pop so the ticks are current.
    func showBehaviorContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let toggles: [(String, Selector, Bool, String)] = [
            ("Chase cursor when idle", #selector(toggleChase), chaseWhenIdle,
             "cursorarrow.motionlines"),
            ("Antics When Bored", #selector(toggleAntics), anticsEnabled, "figure.wave"),
            ("Show Activity Bubbles", #selector(toggleBubbles), bubblesEnabled, "bubble.left"),
        ]
        for (title, action, on, symbol) in toggles {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = on ? .on : .off
            item.image = menuSymbol(symbol)
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func refreshMenu() {
        statusRow?.title = statusSummary()
        visItem?.title = hidden ? "Show Pet" : "Hide Pet"
        chaseItem?.state = chaseWhenIdle ? .on : .off
        anticsItem?.state = anticsEnabled ? .on : .off
        bubbleItem?.state = bubblesEnabled ? .on : .off
        chimeItem?.state = chimeEnabled ? .on : .off
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === mainMenu { refreshMenu() }
        if menu === skinMenu {
            reloadSkins()
            populateSkinMenu()
        }
        if menu === pluginMenu { populatePluginMenu() }
        if menu === sizeMenu { buildSizeMenu() }
        if menu === iconMenu { populateIconMenu() }
        if menu === followMenu { populateFollowMenu() }
        if menu === behaviorMenu { refreshMenu() }  // keep the toggles current
    }

    func statusSummary() -> String {
        if hidden { return "Hidden — \(liveSummary().lowercased())" }
        return liveSummary()
    }

    func liveSummary() -> String {
        switch view.pose {
        case .working: return "Working — \(lastTool.isEmpty ? "tool" : lastTool)"
        case .thinking: return "Claude is thinking"
        case .alert: return "Waiting for you"
        case .failed: return "A tool failed"
        case .celebrate: return "Just finished"
        case .sleeping: return "Asleep"
        default: return "Idle"
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
                let it = NSMenuItem(
                    title: pet.name, action: #selector(setSpritePet(_:)),
                    keyEquivalent: "")
                it.target = self; it.tag = i
                it.state = pet.id == currentID ? .on : .off
                // alt-click removes an installed pet
                let alt = NSMenuItem(
                    title: "Remove \(pet.name)",
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
        for (title, sel) in [
            ("Install Skin from codex-pets.net…", #selector(installSpritePet)),
            ("Browse codex-pets.net", #selector(browseSpritePets)),
            ("Import Skin…", #selector(importSkin)),
            ("Export Current Skin…", #selector(exportSkin)),
        ] {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            skinMenu.addItem(it)
        }

        skinMenu.addItem(.separator())
        let folderRow = NSMenuItem(
            title: "Config: \(Self.tildePath(SkinStore.configDir))",
            action: nil, keyEquivalent: "")
        folderRow.isEnabled = false
        skinMenu.addItem(folderRow)

        var tail: [(String, Selector)] = [
            ("Open Config Folder", #selector(openSkinsFolder)),
            ("Change Config Folder…", #selector(changeConfigFolder)),
        ]
        if SkinStore.isCustomConfigDir && !SkinStore.configDirIsFromEnvironment {
            tail.append(("Use Default Location", #selector(useDefaultConfigFolder)))
        }
        tail.append(("Reload Skins", #selector(reloadSkinsMenu)))
        for (title, sel) in tail {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            if title == "Change Config Folder…" && SkinStore.configDirIsFromEnvironment {
                it.action = nil  // $PET_CONFIG_DIR wins; nothing to change
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
            let it = NSMenuItem(
                title: title, action: #selector(togglePlugin(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = registered ? .on : .off
            it.isEnabled = host.isPresent || registered
            pluginMenu.addItem(it)
        }

        pluginMenu.addItem(.separator())
        let hint = NSMenuItem(
            title: "Tick an agent to let it drive the pet",
            action: nil, keyEquivalent: "")
        hint.isEnabled = false
        pluginMenu.addItem(hint)

        // a folder we manage that an older install left hooks in
        let managed = Set(
            HookHost.claude.files.map {
                $0.deletingLastPathComponent().standardizedFileURL.path
            })
        for dir in HookHost.otherClaudeDirs(besides: managed)
        where HookPlugin.registeredCount(in: dir.appendingPathComponent("settings.json")) > 0 {
            let it = NSMenuItem(
                title: "Also in \(CLI.tilde(dir)) — remove",
                action: #selector(removeStrayPlugin(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = dir
            pluginMenu.addItem(it)
        }
    }
}
