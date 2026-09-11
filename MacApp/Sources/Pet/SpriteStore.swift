//  SpriteStore.swift
//  Desktop Pet
//
//  Where sprite packs live.

import Cocoa

enum SpriteStore {
    static var directory: URL { SkinStore.configDir.appendingPathComponent("pets", isDirectory: true) }

    static func folders() -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return found.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("pet.json").path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func load() -> [SpritePet] {
        folders().compactMap { SpritePet(folder: $0) }
    }

    static func load(id: String) -> SpritePet? {
        folders().first { $0.lastPathComponent == id }.flatMap { SpritePet(folder: $0) }
            ?? load().first { $0.id == id }
    }
}

// MARK: - The pet (all art drawn in code, no assets)
