//  AppDelegate+Art.swift
//  Desktop Pet
//
//  Choosing, importing and exporting skins and sprite packs.

import Cocoa
import UniformTypeIdentifiers

extension AppDelegate {

    @objc func changeConfigFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose Config Folder"
        panel.message = "Skins are read from a \"skins\" folder inside the folder you choose."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = SkinStore.configDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SkinStore.setConfigDir(url)
        reloadSkins()
        populateSkinMenu()
        flash("config moved")
    }

    @objc func useDefaultConfigFolder() {
        SkinStore.setConfigDir(nil)
        reloadSkins()
        populateSkinMenu()
        flash("default location")
    }

    /// One row per agent: ticked when the pet is wired into it, and clicking
    /// installs or removes the hooks.

    @objc func reloadSkinsMenu() { reloadSkins(); populateSkinMenu(); flash("skins reloaded") }

    @objc func openSkinsFolder() {
        SkinStore.seedIfEmpty()
        NSWorkspace.shared.open(SkinStore.configDir)
    }

    @objc func browseSpritePets() {
        if let url = URL(string: "https://codex-pets.net") { NSWorkspace.shared.open(url) }
    }

    /// Ask for a link or an id, then fetch and install in the background so
    /// the pet keeps animating while it downloads.
    @objc func installSpritePet() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Install a skin from codex-pets.net"
        alert.informativeText = "Paste a link such as\n"
                              + "https://codex-pets.net/#/pets/gugakurumiusa\n\n"
                              + "or just the id:  gugakurumiusa"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "link or id"
        if let clip = NSPasteboard.general.string(forType: .string),
           SpriteInstaller.petID(from: clip) != nil, clip.contains("codex-pets.net") {
            field.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let source = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        guard SpriteInstaller.looksValid(source) else {
            report(error: "\"\(source)\" is not a pet id or a codex-pets.net link.")
            return
        }

        flash("installing…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try SpriteInstaller.install(source) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let pet):
                    self.reloadSkins()
                    _ = self.applyArt(id: pet.id)
                    self.populateSkinMenu()
                    self.refreshMenu()
                case .failure(let error):
                    self.flash("install failed")
                    self.report(error: error.localizedDescription)
                }
            }
        }
    }

    func report(error message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Could not install that skin"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc func importSkin() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Import Skin"
        panel.message = "A .petskin file, or a codex-pets.net pack (folder or .zip)"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true          // packs arrive as folders
        var types: [UTType] = [.json, .zip, .folder]
        if let t = UTType(filenameExtension: "petskin") { types.append(t) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return }

        var selected: String?
        for src in panel.urls {
            if isSpritePack(src) {                  // a codex-pets.net pack
                do { selected = try SpriteInstaller.install(src.path).id }
                catch { alert("Could not import \(src.lastPathComponent)", error.localizedDescription) }
                continue
            }
            do {
                let skin = try Skin(contentsOf: src)       // validate before copying
                let dest = SkinStore.userDir.appendingPathComponent(src.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
                selected = skin.id
            } catch {
                alert("Could not import \(src.lastPathComponent)", error.localizedDescription)
            }
        }
        reloadSkins()
        if let selected { _ = applyArt(id: selected) }
        populateSkinMenu()
    }

    /// A spritesheet pack: a folder holding pet.json, or any zip.
    func isSpritePack(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("pet.json").path)
        }
        return url.pathExtension.lowercased() == "zip"
    }

    @objc func exportSkin() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Export Skin"

        if let pet = view.sprite {                  // a pack, exported as a zip
            panel.nameFieldStringValue = "\(pet.id).codex-pet.zip"
            panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? FileManager.default.removeItem(at: url)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", pet.folder.path, url.path]
            try? ditto.run()
            ditto.waitUntilExit()
            if ditto.terminationStatus == 0 { flash("exported") }
            else { alert("Could not export \(pet.name)", "The pack could not be archived.") }
            return
        }

        panel.nameFieldStringValue = "\(view.skin.id).petskin"
        if let t = UTType(filenameExtension: "petskin") { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try view.skin.write(to: url); flash("exported") }
        catch { alert("Could not export skin", error.localizedDescription) }
    }

    func alert(_ title: String, _ detail: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.alertStyle = .warning
        a.runModal()
    }

    func flash(_ text: String) {
        flashText = text
        flashUntil = Date().addingTimeInterval(1.6)
    }

    /// Select by id across both vector skins and sprite pets.
    func applyArt(id: String) -> Bool {
        if let pet = sprites.first(where: { $0.id == id }) {
            view.sprite = pet
            view.spriteFrame = 0
            applyWindowSize()
            Prefs.store.set(id, forKey: "petSkin")
            flash(pet.name.lowercased())
            view.needsDisplay = true
            writeRuntime()
            return true
        }
        if let skin = skins.first(where: { $0.id == id }) {
            view.sprite = nil
            apply(skin)
            return true
        }
        return false
    }

    func apply(_ sk: Skin) {
        view.sprite = nil
        view.skin = sk
        applyWindowSize()
        defer { writeRuntime() }
        Prefs.store.set(sk.id, forKey: "petSkin")
        flash(sk.name.lowercased())
        view.needsDisplay = true
    }

    @objc func removeSpritePet(_ item: NSMenuItem) {
        guard item.tag < sprites.count else { return }
        let pet = sprites[item.tag]
        try? FileManager.default.removeItem(at: pet.folder)
        reloadSkins()
        if view.sprite?.id == pet.id, let first = skins.first { apply(first) }
        populateSkinMenu()
        flash("removed \(pet.name.lowercased())")
    }

    @objc func setSpritePet(_ item: NSMenuItem) {
        guard item.tag < sprites.count else { return }
        _ = applyArt(id: sprites[item.tag].id)
        populateSkinMenu()
    }

    @objc func setSkin(_ item: NSMenuItem) {
        guard item.tag < skins.count else { return }
        let sk = skins[item.tag]
        apply(sk)
        populateSkinMenu()
    }

    /// Make `pet` available after a drag-install from the disk image. Only
    /// ever creates or repoints a symlink to a Pet.app — another program
}
