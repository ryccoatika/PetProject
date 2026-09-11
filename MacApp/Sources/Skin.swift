//  Skin.swift
//  Desktop Pet
//
//  A drawn skin: a palette plus silhouette traits, loaded from a .petskin file.

import Cocoa

enum Crest: String, Codable { case ears, floppy, round, spikes }

/// On-disk shape of a skin file. Traits are optional so a hand-written skin
/// only has to name what it wants.

struct SkinDoc: Codable {
    struct Colors: Codable {
        var body: String, bodyDark: String, belly: String, ink: String, accent: String
    }
    struct Traits: Codable {
        var crest: String
        var stripes: Bool?, whiskers: Bool?, snout: Bool?
        var eyePatches: Bool?, darkLimbs: Bool?
    }
    var id: String
    var name: String
    var colors: Colors
    var traits: Traits
}

struct SkinError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Skin {
    let id: String
    let name: String
    let body: NSColor
    let bodyDark: NSColor
    let belly: NSColor
    let ink: NSColor
    let accent: NSColor        // inner ear / nose
    let crest: Crest
    let stripes: Bool
    let whiskers: Bool
    let snout: Bool            // broad muzzle patch + rounded nose
    let eyePatches: Bool       // dark markings around the eyes
    let darkLimbs: Bool        // legs, tail and paws in the dark tone

    /// Emergency skin, used only if no skin file can be found at all.
    static let fallback = Skin(
        id: "tabby", name: "Tabby cat",
        body: hex("#F5AB5C"), bodyDark: hex("#D9853D"), belly: hex("#FFF0D9"),
        ink: hex("#33241C"), accent: hex("#F599A1"),
        crest: .ears, stripes: true, whiskers: true,
        snout: false, eyePatches: false, darkLimbs: false)

    // MARK: colour conversion

    static func hex(_ string: String) -> NSColor { (try? parse(string)) ?? .gray }

    static func parse(_ string: String) throws -> NSColor {
        var t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6 || t.count == 8, let v = UInt64(t, radix: 16) else {
            throw SkinError(message: "\"\(string)\" is not a #RRGGBB colour")
        }
        let hasAlpha = t.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func hexString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    // MARK: file <-> model

    init(doc: SkinDoc) throws {
        guard !doc.id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SkinError(message: "missing \"id\"")
        }
        guard let crest = Crest(rawValue: doc.traits.crest.lowercased()) else {
            throw SkinError(message: "unknown crest \"\(doc.traits.crest)\" "
                          + "(use ears, floppy, round or spikes)")
        }
        id = doc.id
        name = doc.name.isEmpty ? doc.id : doc.name
        body     = try Skin.parse(doc.colors.body)
        bodyDark = try Skin.parse(doc.colors.bodyDark)
        belly    = try Skin.parse(doc.colors.belly)
        ink      = try Skin.parse(doc.colors.ink)
        accent   = try Skin.parse(doc.colors.accent)
        self.crest = crest
        stripes    = doc.traits.stripes    ?? false
        whiskers   = doc.traits.whiskers   ?? false
        snout      = doc.traits.snout      ?? false
        eyePatches = doc.traits.eyePatches ?? false
        darkLimbs  = doc.traits.darkLimbs  ?? false
    }

    init(id: String, name: String, body: NSColor, bodyDark: NSColor, belly: NSColor,
         ink: NSColor, accent: NSColor, crest: Crest, stripes: Bool, whiskers: Bool,
         snout: Bool, eyePatches: Bool, darkLimbs: Bool) {
        self.id = id; self.name = name
        self.body = body; self.bodyDark = bodyDark; self.belly = belly
        self.ink = ink; self.accent = accent
        self.crest = crest; self.stripes = stripes; self.whiskers = whiskers
        self.snout = snout; self.eyePatches = eyePatches; self.darkLimbs = darkLimbs
    }

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let doc: SkinDoc
        do { doc = try JSONDecoder().decode(SkinDoc.self, from: data) }
        catch { throw SkinError(message: "not a valid skin file (\(error.localizedDescription))") }
        try self.init(doc: doc)
    }

    var doc: SkinDoc {
        SkinDoc(id: id, name: name,
                colors: .init(body: Skin.hexString(body), bodyDark: Skin.hexString(bodyDark),
                              belly: Skin.hexString(belly), ink: Skin.hexString(ink),
                              accent: Skin.hexString(accent)),
                traits: .init(crest: crest.rawValue, stripes: stripes, whiskers: whiskers,
                              snout: snout, eyePatches: eyePatches, darkLimbs: darkLimbs))
    }

    func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(doc).write(to: url)
    }
}

/// Where skins live and how they are discovered.
