//  AppDelegate+TrayIcon.swift
//  Desktop Pet
//
//  What the menu bar icon shows: the app icon, the current skin, or an
//  SF Symbol of the user's choosing.

import Cocoa

extension AppDelegate {

    /// Stored in preferences as "appicon", "skin" or "symbol:<name>".
    var trayIconChoice: String {
        Prefs.store.string(forKey: "petTrayIcon") ?? "appicon"
    }

    static let trayIconSymbols: [(title: String, symbol: String)] = [
        ("Paw Print", "pawprint.fill"),
        ("Cat", "cat.fill"),
        ("Dog", "dog.fill"),
        ("Bird", "bird.fill"),
        ("Lizard", "lizard.fill"),
        ("Tortoise", "tortoise.fill"),
    ]

    /// The emoji standing in for a drawn skin. Sprite pets draw their own
    /// idle frame instead.
    static func emoji(forSkin id: String) -> String {
        switch id {
        case "tabby": return "🐈"
        case "dog": return "🐶"
        case "panda": return "🐼"
        case "dino": return "🦕"
        default: return "🐾"
        }
    }

    func applyTrayIcon() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.image = nil
        lastTraySignature = ""  // force the next animation tick to redraw

        let choice = trayIconChoice
        if choice == "skin" {
            if let pet = view.sprite {
                button.image = Self.spriteThumbnail(pet, track: view.spriteTrack, frame: 0)
            } else {
                button.title = Self.emoji(forSkin: view.skin.id)
            }
        } else if choice.hasPrefix("symbol:") {
            let name = String(choice.dropFirst("symbol:".count))
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "pet") {
                image.isTemplate = true  // follows the menu bar's light/dark look
                button.image = image
            }
        }
        if button.image == nil && button.title.isEmpty {  // appicon, or a fallback
            button.image = Self.appIconThumbnail()
        }
    }

    /// The app icon at menu bar size.
    static func appIconThumbnail() -> NSImage {
        let icon = NSApp.applicationIconImage ?? NSImage()
        let thumb = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return thumb
    }

    /// A sprite pet frame at menu bar size. Not a template image — sprite art
    /// is full colour, so it keeps its own colours in the menu bar.
    static func spriteThumbnail(_ pet: SpritePet, track: SpritePet.Track, frame: Int) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            pet.draw(track: track, frame: frame, in: rect)
            return true
        }
    }

    /// When the menu bar icon is following the skin and that skin is a sprite
    /// pet, redraw it from the pet's current track and frame so it animates
    /// in step with the pet itself. Cheap: only when the frame changed, and a
    /// no-op for drawn skins (a static emoji) or any other icon choice.
    func animateTrayIfNeeded() {
        guard trayIconChoice == "skin", let pet = view.sprite,
            let button = statusItem?.button
        else { return }
        let signature = "\(view.spriteTrack)|\(view.spriteFrame)"
        guard signature != lastTraySignature else { return }
        lastTraySignature = signature
        button.image = Self.spriteThumbnail(pet, track: view.spriteTrack, frame: view.spriteFrame)
    }

    /// Rebuilt on every open, so the tick and symbol availability stay right.
    func populateIconMenu() {
        iconMenu.removeAllItems()
        let current = trayIconChoice

        func row(_ title: String, _ value: String, image: NSImage? = nil) {
            let it = NSMenuItem(title: title, action: #selector(setTrayIcon(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = value
            it.state = current == value ? .on : .off
            it.image = image
            iconMenu.addItem(it)
        }

        row("App Icon", "appicon")
        row("Current Skin", "skin")
        iconMenu.addItem(.separator())
        for (title, symbol) in Self.trayIconSymbols {
            // older macOS misses some of these; only offer what exists
            guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            else { continue }
            image.isTemplate = true
            row(title, "symbol:\(symbol)", image: image)
        }
        // a custom symbol that is none of the presets still shows its tick
        if current.hasPrefix("symbol:"),
            !Self.trayIconSymbols.contains(where: { "symbol:\($0.symbol)" == current })
        {
            row(String(current.dropFirst("symbol:".count)), current)
        }
        iconMenu.addItem(.separator())
        let custom = NSMenuItem(
            title: "Custom SF Symbol…", action: #selector(chooseCustomTrayIcon),
            keyEquivalent: "")
        custom.target = self
        iconMenu.addItem(custom)
    }

    @objc func setTrayIcon(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String else { return }
        Prefs.store.set(value, forKey: "petTrayIcon")
        applyTrayIcon()
        populateIconMenu()
    }

    @objc func chooseCustomTrayIcon() {
        let alert = NSAlert()
        alert.messageText = "Custom menu bar icon"
        alert.informativeText =
            "The name of any SF Symbol, as the SF Symbols app spells it — "
            + "for example \"pawprint.circle.fill\"."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        if trayIconChoice.hasPrefix("symbol:") {
            field.stringValue = String(trayIconChoice.dropFirst("symbol:".count))
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Use Symbol")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
            NSImage(systemSymbolName: name, accessibilityDescription: name) != nil
        else {
            let sorry = NSAlert()
            sorry.messageText = "No symbol called \"\(name)\""
            sorry.informativeText =
                "This version of macOS does not know that symbol. The SF Symbols "
                + "app shows every name it does know."
            sorry.runModal()
            return
        }
        Prefs.store.set("symbol:\(name)", forKey: "petTrayIcon")
        applyTrayIcon()
        populateIconMenu()
    }
}
