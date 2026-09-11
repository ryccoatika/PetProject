//  SkinStore.swift
//  Desktop Pet
//
//  Where skins live, how they are discovered and seeded.

import Cocoa

enum SkinStore {
    static let extensions = ["petskin", "json"]
    static let configKey = "petConfigDir"

    /// Config folder, in precedence order:
    ///   1. $PET_CONFIG_DIR   2. the folder chosen in the menu   3. ~/.config/pet
    static var configDir: URL {
        if let env = ProcessInfo.processInfo.environment["PET_CONFIG_DIR"],
            !env.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return expand(env)
        }
        if let chosen = Prefs.store.string(forKey: configKey),
            !chosen.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return expand(chosen)
        }
        return defaultConfigDir
    }

    static var defaultConfigDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
            ".config/pet",
            isDirectory: true)
    }

    /// True when the location has been overridden away from the default.
    static var isCustomConfigDir: Bool {
        configDir.standardizedFileURL != defaultConfigDir.standardizedFileURL
    }

    /// Only the menu-chosen override can be cleared; the env var always wins.
    static var configDirIsFromEnvironment: Bool {
        let env = ProcessInfo.processInfo.environment["PET_CONFIG_DIR"] ?? ""
        return !env.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func setConfigDir(_ url: URL?) {
        let d = Prefs.store
        if let url { d.set(url.path, forKey: configKey) } else { d.removeObject(forKey: configKey) }
    }

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// User-editable skin folder; everything shown in the menu comes from here.
    static var userDir: URL { configDir.appendingPathComponent("skins", isDirectory: true) }

    /// Skins folder used by builds before the move to ~/.config/pet.
    static var legacyDir: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)[0]
        return base.appendingPathComponent("DesktopPet/Skins", isDirectory: true)
    }

    /// Read-only copies shipped with the app, used to seed the folder.
    static var seedDirs: [URL] {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Skins")) }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        dirs.append(exeDir.appendingPathComponent("Skins"))
        dirs.append(exeDir.deletingLastPathComponent().appendingPathComponent("Skins"))
        return dirs
    }

    static func files(in dir: URL) -> [URL] {
        let found =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
        return found.filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    /// Fill an empty skins folder: first from an older install's folder, so a
    /// custom skin survives the move, otherwise from the copies shipped with
    /// the app. Deleting the folder therefore restores the defaults.
    @discardableResult
    static func seedIfEmpty() -> Bool {
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        guard files(in: userDir).isEmpty else { return false }
        for dir in [legacyDir] + seedDirs {
            guard dir.standardizedFileURL != userDir.standardizedFileURL else { continue }
            let source = files(in: dir)
            guard !source.isEmpty else { continue }
            for f in source {
                try? FileManager.default.copyItem(
                    at: f, to: userDir.appendingPathComponent(f.lastPathComponent))
            }
            return true
        }
        return writeEmbeddedDefaults()
    }

    /// Last resort, and the one that always works: the default skins are
    /// compiled into the binary, so a fresh install has them even with no
    /// skins folder and no Resources in the bundle.
    @discardableResult
    static func writeEmbeddedDefaults() -> Bool {
        var wrote = false
        for (name, json) in DefaultSkinData.files {
            let dest = userDir.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            if (try? json.write(to: dest, atomically: true, encoding: .utf8)) != nil {
                wrote = true
            }
        }
        return wrote
    }

    /// Decode the compiled-in defaults without touching the disk at all.
    static var embeddedSkins: [Skin] {
        DefaultSkinData.files.compactMap { _, json in
            guard let data = json.data(using: .utf8),
                let doc = try? JSONDecoder().decode(SkinDoc.self, from: data)
            else { return nil }
            return try? Skin(doc: doc)
        }
    }

    static func load() -> (skins: [Skin], errors: [String]) {
        seedIfEmpty()
        var skins: [Skin] = [], errors: [String] = []
        for f in files(in: userDir).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do { skins.append(try Skin(contentsOf: f)) } catch {
                errors.append("\(f.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        skins.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if skins.isEmpty { skins = embeddedSkins }  // folder unwritable? use memory
        if skins.isEmpty { skins = [.fallback] }
        return (skins, errors)
    }
}

// MARK: - Sprite pets (codex-pets.net spritesheets)

/// A spritesheet pet: a folder holding pet.json and a spritesheet image.
///
/// The atlas convention is 8 columns of 192x208 cells; v1 sheets have 9 rows
/// and v2 sheets 11, the last two being free for the client. Frame counts per
/// row are measured from the image rather than assumed, because published
/// packs do not always match the documented counts.
