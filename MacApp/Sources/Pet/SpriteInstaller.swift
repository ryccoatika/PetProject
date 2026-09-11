//  SpriteInstaller.swift
//  Desktop Pet
//
//  Installing sprite packs from the marketplace, a URL, or disk.

import Cocoa

enum SpriteInstaller {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// True when the source has to be fetched rather than copied from disk.
    static func isRemote(_ source: String) -> Bool {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileManager.default.fileExists(atPath: SkinStore.expand(text).path) { return false }
        return true
    }

    /// Pull the pet id out of whatever the user pasted:
    ///   gugakurumiusa
    ///   https://codex-pets.net/#/pets/gugakurumiusa
    ///   https://codex-pets.net/pets/gugakurumiusa
    ///   https://codex-pets.net/api/pets/gugakurumiusa/download?v=123
    static func petID(from source: String) -> String? {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let query = text.firstIndex(of: "?") { text = String(text[..<query]) }
        // a link to somewhere else is not a marketplace id
        if text.lowercased().hasPrefix("http"), !text.lowercased().contains("codex-pets.net") {
            return nil
        }
        if text.lowercased().hasPrefix("http") || text.contains("/") {
            let parts = text
                .replacingOccurrences(of: "#", with: "/")
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != "https:" && $0 != "http:" }
            if let index = parts.lastIndex(of: "pets"), index + 1 < parts.count {
                return clean(parts[index + 1])
            }
            // a bare .../download URL, or something unexpected
            if let last = parts.last, last != "download" { return clean(last) }
            if parts.count >= 2 { return clean(parts[parts.count - 2]) }
            return nil
        }
        return clean(text)
    }

    private static func clean(_ id: String) -> String? {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            return nil
        }
        return trimmed
    }

    /// Where to fetch from and what to call the pack once it lands.
    static func remoteSource(_ source: String) -> (url: URL, id: String)? {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // a direct link to an archive is used as given, wherever it is hosted
        if text.lowercased().hasPrefix("http"), text.lowercased().hasSuffix(".zip"),
           let url = URL(string: text) {
            let name = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: ".codex-pet", with: "")
            guard let id = clean(name) else { return nil }
            return (url, id)
        }
        guard let id = petID(from: text),
              let url = URL(string: "https://codex-pets.net/api/pets/\(id)/download")
        else { return nil }
        return (url, id)
    }

    static func downloadURL(for source: String) -> URL? { remoteSource(source)?.url }

    /// True when the source names something installable.
    static func looksValid(_ source: String) -> Bool {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileManager.default.fileExists(atPath: SkinStore.expand(text).path) { return true }
        return remoteSource(text) != nil
    }

    @discardableResult
    static func install(_ source: String) throws -> SpritePet {
        let fm = FileManager.default
        try? fm.createDirectory(at: SpriteStore.directory, withIntermediateDirectories: true)

        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = SkinStore.expand(text)
        if fm.fileExists(atPath: local.path) {
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: local.path, isDirectory: &isDir)
            let id = local.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: ".codex-pet", with: "")
            return isDir.boolValue ? try copyFolder(local, id: id)
                                   : try unpack(zip: local, id: id)
        }

        guard let remote = remoteSource(text) else {
            throw Failure(message: "\"\(text)\" is not a pet id, a codex-pets.net link, "
                                 + "or a file on disk")
        }
        let (url, id) = remote
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw Failure(message: "could not download \(url.absoluteString) — check the id "
                                 + "and your connection")
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(id).codex-pet.zip")
        try? data.write(to: tmp)
        defer { try? fm.removeItem(at: tmp) }
        return try unpack(zip: tmp, id: id)
    }

    private static func unpack(zip: URL, id: String) throws -> SpritePet {
        let dest = SpriteStore.directory.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", zip.path, "-d", dest.path]
        try? unzip.run()
        unzip.waitUntilExit()
        return try finish(dest)
    }

    private static func copyFolder(_ folder: URL, id: String) throws -> SpritePet {
        let dest = SpriteStore.directory.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: folder, to: dest) }
        catch { throw Failure(message: "could not copy \(folder.path): \(error.localizedDescription)") }
        return try finish(dest)
    }

    /// Some packs unzip into a nested folder; flatten that, then validate.
    private static func finish(_ dest: URL) throws -> SpritePet {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dest.appendingPathComponent("pet.json").path) {
            let inner = ((try? fm.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)) ?? [])
                .first { fm.fileExists(atPath: $0.appendingPathComponent("pet.json").path) }
            if let inner {
                for file in (try? fm.contentsOfDirectory(at: inner, includingPropertiesForKeys: nil)) ?? [] {
                    try? fm.moveItem(at: file, to: dest.appendingPathComponent(file.lastPathComponent))
                }
                try? fm.removeItem(at: inner)
            }
        }
        guard let pet = SpritePet(folder: dest) else {
            try? fm.removeItem(at: dest)
            throw Failure(message: "that does not look like a pet pack "
                                 + "(it needs pet.json and a spritesheet)")
        }
        return pet
    }
}

// MARK: - CLI
