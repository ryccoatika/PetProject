//  CLI+Skins.swift
//  Desktop Pet
//
//  Commands for skins, sprite packs and the config folder.

import Cocoa

extension CLI {

    // MARK: skins

    static func listSkins() {
        Prefs.refresh()
        let current = Prefs.store.string(forKey: "petSkin") ?? "tabby"
        let result = SkinStore.load()
        for skin in result.skins {
            print("\(skin.id == current ? " * " : "   ")\(skin.id.padding(toLength: max(10, skin.id.count + 1), withPad: " ", startingAt: 0))\(skin.name)")
        }
        for pet in SpriteStore.load() {
            print("\(pet.id == current ? " * " : "   ")"
                + "\(pet.id.padding(toLength: max(10, pet.id.count + 1), withPad: " ", startingAt: 0))"
                + "\(pet.name)   (sprite)")
        }
        for error in result.errors { print("  !  \(error)") }
    }

    // MARK: sprite pets

    static func pets(_ args: [String]) {
        switch args.first {
        case nil, "list":
            let installed = SpriteStore.load()
            if installed.isEmpty {
                print("no sprite pets installed — try: pet pets install <id>")
                print("browse them at https://codex-pets.net")
                return
            }
            Prefs.refresh()
            let current = Prefs.store.string(forKey: "petSkin") ?? ""
            for pet in installed {
                let mark = pet.id == current ? " * " : "   "
                let rows = pet.frameCounts.prefix(9).map(String.init).joined(separator: ",")
                print("\(mark)\(pet.id.padding(toLength: max(20, pet.id.count + 1), withPad: " ", startingAt: 0))"
                    + "\(pet.name)   [\(pet.rows) rows, frames \(rows)]")
            }
            print("")
            print("folder: \(tilde(SpriteStore.directory))")
        case "dir":
            print(SpriteStore.directory.path)
        case "install":
            guard let what = args.dropFirst().first else {
                fail("usage: pet pets install <id | url | folder | zip>")
            }
            installPet(what)
        case "remove", "uninstall":
            guard let id = args.dropFirst().first else { fail("usage: pet pets remove <id>") }
            let folder = SpriteStore.directory.appendingPathComponent(id)
            guard FileManager.default.fileExists(atPath: folder.path) else {
                fail("no sprite pet \"\(id)\" installed")
            }
            try? FileManager.default.removeItem(at: folder)
            print("removed \(tilde(folder))")
            if Prefs.store.string(forKey: "petSkin") == id {
                Prefs.store.set("tabby", forKey: "petSkin")
                Prefs.store.synchronize()
            }
            Prefs.notifyRunningApp()
        default:
            fail("usage: pet pets [list | install <id|url|folder|zip> | remove <id> | dir]")
        }
    }

    /// Accepts a marketplace id, a codex-pets.net link, a direct URL, or a
    /// local folder or .zip.
    static func installPet(_ source: String) {
        if SpriteInstaller.isRemote(source), let url = SpriteInstaller.downloadURL(for: source) {
            print("downloading \(url.absoluteString)…")
        }
        do {
            let pet = try SpriteInstaller.install(source)
            print("installed \(pet.name) (\(pet.id)) — \(pet.rows) rows, "
                + "\(Int(pet.cell.width))x\(Int(pet.cell.height)) frames")
            print("use it with: pet skin \(pet.id)")
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func setSkin(_ id: String?) {
        guard let id else { fail("usage: pet skin <id>   (see: pet skins)") }
        let skins = SkinStore.load().skins
        let spriteIDs = SpriteStore.load().map(\.id)
        guard skins.contains(where: { $0.id == id }) || spriteIDs.contains(id) else {
            fail("no skin \"\(id)\" — available: "
                 + (skins.map(\.id) + spriteIDs).joined(separator: ", "))
        }
        Prefs.store.set(id, forKey: "petSkin")
        Prefs.store.synchronize()
        Prefs.notifyRunningApp()
        print("skin set to \(id)")
    }

    // MARK: config

    static func config(_ args: [String]) {
        switch args.first {
        case nil:
            let source = SkinStore.configDirIsFromEnvironment ? "$PET_CONFIG_DIR"
                       : SkinStore.isCustomConfigDir ? "set with `pet config set`" : "default"
            print("config dir : \(tilde(SkinStore.configDir))   (\(source))")
            print("skins dir  : \(tilde(SkinStore.userDir))")
        case "set":
            guard args.count > 1 else { fail("usage: pet config set <path>") }
            let url = SkinStore.expand(args[1]).standardizedFileURL
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            catch { fail("cannot create \(url.path): \(error.localizedDescription)") }
            SkinStore.setConfigDir(url)
            Prefs.store.synchronize()
            SkinStore.seedIfEmpty()
            Prefs.notifyRunningApp()
            print("config dir set to \(tilde(url))")
            if SkinStore.configDirIsFromEnvironment {
                print("note: $PET_CONFIG_DIR is set and overrides this")
            }
            if HookPlugin.isRegisteredAnywhere {
                print("note: the Claude hooks now write to the new folder too")
            }
        case "reset":
            SkinStore.setConfigDir(nil)
            Prefs.store.synchronize()
            SkinStore.seedIfEmpty()
            Prefs.notifyRunningApp()
            print("config dir reset to \(tilde(SkinStore.defaultConfigDir))")
        default:
            fail("usage: pet config [set <path> | reset]")
        }
    }
}
