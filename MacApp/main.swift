import Cocoa
import UniformTypeIdentifiers

// MARK: - State

enum Pose { case sitting, grooming, sleeping, running, thinking, working, alert, celebrate }

// MARK: - Preferences

enum Prefs {
    static let domain = "local.desktop.pet"
    static let reloadNotification = "local.desktop.pet.reload"

    /// Always addressed by suite name: the CLI runs from the same binary but
    /// not necessarily as the bundled app, so .standard could differ.
    static var store: UserDefaults { UserDefaults(suiteName: domain) ?? .standard }

    /// Pick up writes made by another process.
    static func refresh() { CFPreferencesAppSynchronize(domain as CFString) }

    static func notifyRunningApp() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(reloadNotification), object: nil, userInfo: nil,
            deliverImmediately: true)
    }
}

// MARK: - Skins (loaded from .petskin resource files, never hardcoded)

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
enum SkinStore {
    static let extensions = ["petskin", "json"]
    static let configKey = "petConfigDir"

    /// Config folder, in precedence order:
    ///   1. $PET_CONFIG_DIR   2. the folder chosen in the menu   3. ~/.config/pet
    static var configDir: URL {
        if let env = ProcessInfo.processInfo.environment["PET_CONFIG_DIR"],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return expand(env)
        }
        if let chosen = Prefs.store.string(forKey: configKey),
           !chosen.trimmingCharacters(in: .whitespaces).isEmpty {
            return expand(chosen)
        }
        return defaultConfigDir
    }

    static var defaultConfigDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/pet",
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
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
        let found = (try? FileManager.default.contentsOfDirectory(
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
            if (try? json.write(to: dest, atomically: true, encoding: .utf8)) != nil { wrote = true }
        }
        return wrote
    }

    /// Decode the compiled-in defaults without touching the disk at all.
    static var embeddedSkins: [Skin] {
        DefaultSkinData.files.compactMap { _, json in
            guard let data = json.data(using: .utf8),
                  let doc = try? JSONDecoder().decode(SkinDoc.self, from: data) else { return nil }
            return try? Skin(doc: doc)
        }
    }

    static func load() -> (skins: [Skin], errors: [String]) {
        seedIfEmpty()
        var skins: [Skin] = [], errors: [String] = []
        for f in files(in: userDir).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do { skins.append(try Skin(contentsOf: f)) }
            catch { errors.append("\(f.lastPathComponent) — \(error.localizedDescription)") }
        }
        skins.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if skins.isEmpty { skins = embeddedSkins }        // folder unwritable? use memory
        if skins.isEmpty { skins = [.fallback] }
        return (skins, errors)
    }
}

// MARK: - The pet (all art drawn in code, no assets)

final class PetView: NSView {
    var pose: Pose = .sitting
    var facingRight = true
    var phase: CGFloat = 0
    var blink: CGFloat = 0
    var eyeOffset = CGPoint.zero
    var zPhase: CGFloat = 0
    var label: String? = nil          // pill text under the pet
    var hop: CGFloat = 0              // celebrate bounce
    var held = false                  // being dragged by the user

    var dragBegin: (() -> Void)?
    var dragMove: ((NSPoint) -> Void)?      // receives the new window origin
    var dragEnd: (() -> Void)?
    var doubleClick: (() -> Void)?
    private var grabOffset = CGSize.zero
    private var dragActive = false

    /// Region the pet actually occupies. Clicks outside it pass through to
    /// whatever is underneath, so the window only "exists" where the cat is.
    var grabRect: NSRect {
        NSRect(x: bounds.midX - 45, y: 0, width: 90, height: 118)
    }

    // The app is an accessory: without this the first click would only
    // activate it instead of starting the drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        guard let w = window else { return }
        if e.clickCount >= 2 { doubleClick?(); return }
        let m = NSEvent.mouseLocation
        grabOffset = CGSize(width: w.frame.origin.x - m.x, height: w.frame.origin.y - m.y)
        dragActive = true
        dragBegin?()                     // parks the pet for the whole gesture
    }
    override func mouseDragged(with e: NSEvent) {
        guard dragActive else { return }
        held = true                      // the held pose waits for real movement
        let m = NSEvent.mouseLocation
        dragMove?(NSPoint(x: m.x + grabOffset.width, y: m.y + grabOffset.height))
    }
    override func mouseUp(with e: NSEvent) {
        guard dragActive else { return }
        dragActive = false
        held = false
        dragEnd?()
    }

    override var isFlipped: Bool { false }

    var skin: Skin = .fallback
    var fur:   NSColor { skin.body }
    var furDk: NSColor { skin.bodyDark }
    var cream: NSColor { skin.belly }
    var ink:   NSColor { skin.ink }
    var pink:  NSColor { skin.accent }
    let screenBg = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.28, alpha: 1)
    let screenLit = NSColor(srgbRed: 0.55, green: 0.85, blue: 0.95, alpha: 1)
    let warn  = NSColor(srgbRed: 0.95, green: 0.45, blue: 0.25, alpha: 1)

    let base: CGFloat = 26            // ground line inside the view

    // MARK: primitives

    private func fillStroke(_ p: NSBezierPath, _ color: NSColor, _ lw: CGFloat = 1.6) {
        color.setFill(); p.fill()
        ink.setStroke(); p.lineWidth = lw; p.lineJoinStyle = .round; p.lineCapStyle = .round; p.stroke()
    }
    private func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat,
                      _ color: NSColor, _ lw: CGFloat = 1.6) {
        fillStroke(NSBezierPath(ovalIn: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h)), color, lw)
    }
    private func plainOval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h)).fill()
    }
    /// Paw / limb colour: pandas wear their dark tone on the extremities.
    private var paw: NSColor { skin.darkLimbs ? furDk : cream }
    private var limbColor: NSColor { skin.darkLimbs ? furDk : fur }

    private func limb(_ from: CGPoint, _ to: CGPoint, _ w: CGFloat = 5) {
        let p = NSBezierPath(); p.move(to: from); p.line(to: to)
        p.lineWidth = w + 2.6; p.lineCapStyle = .round; ink.setStroke(); p.stroke()
        p.lineWidth = w; limbColor.setStroke(); p.stroke()
    }
    private func tail(from: CGPoint, to: CGPoint, c1: CGPoint, c2: CGPoint) {
        let t = NSBezierPath()
        t.move(to: from); t.curve(to: to, controlPoint1: c1, controlPoint2: c2)
        t.lineWidth = 8.6; t.lineCapStyle = .round; ink.setStroke(); t.stroke()
        t.lineWidth = 6; limbColor.setStroke(); t.stroke()
    }

    // MARK: draw

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        let cx = bounds.midX

        NSColor(white: 0, alpha: 0.16).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 20, y: base - 7 + min(hop, 6),
                                    width: 40, height: max(4, 8 - hop * 0.5))).fill()

        NSGraphicsContext.saveGraphicsState()
        if !facingRight {
            let t = NSAffineTransform(); t.translateX(by: bounds.width, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat()
        }
        let up = NSAffineTransform(); up.translateX(by: 0, yBy: hop); up.concat()

        if held {                       // dangling from the user's cursor
            drawHeld()
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        switch pose {
        case .running:   drawRunning()
        case .sitting:   drawSitting(grooming: false)
        case .grooming:  drawSitting(grooming: true)
        case .sleeping:  drawSleeping()
        case .thinking:  drawSitting(grooming: false, tailFlick: true)
        case .alert:     drawAlertPose()
        case .celebrate: drawCelebrate()
        case .working:   drawWorking()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Bubbles and labels are never mirrored, so they live outside the flip.
        switch pose {
        case .sleeping:  drawZs()
        case .thinking:  drawThoughtBubble()
        case .alert:     drawBangBubble()
        case .celebrate: drawSparkles()
        default: break
        }
        if let l = label { drawPill(l) }
    }

    // MARK: poses

    private func drawRunning() {
        let cx = bounds.midX
        let bob = sin(phase * 2) * 1.6, bodyY = base + 15 + bob
        tail(from: CGPoint(x: cx - 15, y: bodyY + 2), to: CGPoint(x: cx - 34, y: bodyY + 12 + sin(phase) * 6),
             c1: CGPoint(x: cx - 24, y: bodyY - 2), c2: CGPoint(x: cx - 32, y: bodyY + 2))
        let sw = sin(phase) * 9, sw2 = sin(phase + .pi) * 9
        limb(CGPoint(x: cx - 10, y: bodyY - 4), CGPoint(x: cx - 10 + sw, y: base + 1))
        limb(CGPoint(x: cx + 8, y: bodyY - 4), CGPoint(x: cx + 8 + sw2, y: base + 1))
        bodyShape(cx, bodyY, 40, 24)
        plainOval(cx - 2, bodyY - 5, 26, 11, cream)
        stripes(cx: cx - 9, y: bodyY + 2)
        limb(CGPoint(x: cx - 4, y: bodyY - 4), CGPoint(x: cx - 4 + sw2, y: base + 1))
        limb(CGPoint(x: cx + 14, y: bodyY - 4), CGPoint(x: cx + 14 + sw, y: base + 1))
        drawHead(at: CGPoint(x: cx + 18, y: bodyY + 12 + bob * 0.5), scale: 1, earPerk: 1)
    }

    private func stripes(cx: CGFloat, y: CGFloat) {
        guard skin.stripes else { return }
        furDk.setFill()
        for i in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: cx + CGFloat(i) * 9, y: y, width: 4, height: 9)).fill()
        }
    }

    /// Torso. Spiked skins get a row of plates poking out behind it.
    private func bodyShape(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        if skin.crest == .spikes {
            for i in 0..<4 {
                let t = CGFloat(i) / 3
                let x = cx - w * 0.34 + w * 0.68 * t
                let peak = h * 0.42 * (0.7 + 0.5 * sin(t * .pi))
                let sp = NSBezierPath()
                sp.move(to: CGPoint(x: x - 6, y: cy + h * 0.22))
                sp.line(to: CGPoint(x: x, y: cy + h * 0.22 + peak))
                sp.line(to: CGPoint(x: x + 6, y: cy + h * 0.22))
                sp.close()
                fillStroke(sp, furDk, 1.4)
            }
        }
        oval(cx, cy, w, h, fur)
    }

    private func drawSitting(grooming: Bool, tailFlick: Bool = false) {
        let cx = bounds.midX
        let breathe = sin(phase * 0.8) * 0.8
        let wag = tailFlick ? sin(phase * 2.4) * 9 : sin(phase * 0.9) * 3
        tail(from: CGPoint(x: cx - 9, y: base + 6), to: CGPoint(x: cx + 18, y: base + 4 + wag),
             c1: CGPoint(x: cx - 30, y: base - 2), c2: CGPoint(x: cx + 6, y: base - 8))
        bodyShape(cx, base + 16 + breathe, 30, 30)
        plainOval(cx + 3, base + 12, 16, 16, cream)
        oval(cx - 11, base + 9, 18, 16, fur)
        oval(cx + 6, base + 4, 9, 7, paw, 1.4)
        oval(cx + 14, base + 4, 9, 7, paw, 1.4)
        let headY = base + 38 + breathe
        if grooming { limb(CGPoint(x: cx + 8, y: base + 16), CGPoint(x: cx + 15, y: headY - 6)) }
        drawHead(at: CGPoint(x: cx + 4, y: headY), scale: 1, earPerk: tailFlick ? 1.15 : 1)
    }

    private func drawSleeping() {
        let cx = bounds.midX
        let breathe = sin(phase * 0.6) * 1.4
        tail(from: CGPoint(x: cx - 20, y: base + 10), to: CGPoint(x: cx + 20, y: base + 5),
             c1: CGPoint(x: cx - 26, y: base - 6), c2: CGPoint(x: cx + 6, y: base - 6))
        bodyShape(cx - 2, base + 14 + breathe, 46, 24 + breathe)
        stripes(cx: cx - 12, y: base + 17)
        oval(cx + 14, base + 6, 12, 8, paw, 1.4)
        drawHead(at: CGPoint(x: cx + 17, y: base + 15), scale: 0.92, earPerk: 0.55, asleep: true)
    }

    /// Sitting at a tiny laptop, paws typing.
    private func drawWorking() {
        let cx = bounds.midX
        let breathe = sin(phase * 0.9) * 0.7
        tail(from: CGPoint(x: cx - 12, y: base + 6), to: CGPoint(x: cx - 30, y: base + 6 + sin(phase * 2.2) * 8),
             c1: CGPoint(x: cx - 22, y: base - 2), c2: CGPoint(x: cx - 30, y: base - 2))
        bodyShape(cx, base + 18 + breathe, 32, 32)                       // body
        drawHead(at: CGPoint(x: cx, y: base + 42 + breathe), scale: 1, earPerk: 1.1)

        // laptop: lid behind the paws, deck in front
        let lid = NSBezierPath(roundedRect: NSRect(x: cx - 21, y: base + 8, width: 42, height: 22),
                               xRadius: 3, yRadius: 3)
        fillStroke(lid, screenBg)
        screenLit.withAlphaComponent(0.9).setFill()
        for i in 0..<3 {                                                  // scrolling "code"
            let t = (phase * 0.35 + CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let w = 8 + CGFloat((i * 7) % 17)
            NSBezierPath(rect: NSRect(x: cx - 17, y: base + 26 - t * 16, width: w, height: 2)).fill()
        }
        let deck = NSBezierPath(roundedRect: NSRect(x: cx - 25, y: base + 2, width: 50, height: 7),
                                xRadius: 3, yRadius: 3)
        fillStroke(deck, NSColor(white: 0.85, alpha: 1))

        for (i, dx) in [-11.0 as CGFloat, 11.0].enumerated() {            // typing paws
            let tap = max(0, sin(phase * 3.4 + CGFloat(i) * .pi)) * 4
            oval(cx + dx, base + 9 + tap, 11, 8, paw, 1.4)
        }
    }

    private func drawAlertPose() {
        let cx = bounds.midX
        let perk = 1.25 + sin(phase * 4) * 0.12
        tail(from: CGPoint(x: cx - 9, y: base + 6), to: CGPoint(x: cx + 6, y: base + 26 + sin(phase * 4) * 4),
             c1: CGPoint(x: cx - 26, y: base + 4), c2: CGPoint(x: cx + 2, y: base + 6))
        bodyShape(cx, base + 18, 28, 34)                                  // sitting tall
        plainOval(cx + 2, base + 14, 15, 18, cream)
        oval(cx + 5, base + 4, 9, 7, paw, 1.4)
        oval(cx + 13, base + 4, 9, 7, paw, 1.4)
        drawHead(at: CGPoint(x: cx + 3, y: base + 44), scale: 1, earPerk: perk)
    }

    private func drawCelebrate() {
        let cx = bounds.midX
        let splay = sin(phase * 2) * 6
        tail(from: CGPoint(x: cx - 13, y: base + 16), to: CGPoint(x: cx - 30, y: base + 34),
             c1: CGPoint(x: cx - 26, y: base + 14), c2: CGPoint(x: cx - 32, y: base + 22))
        limb(CGPoint(x: cx - 8, y: base + 12), CGPoint(x: cx - 16 - splay, y: base + 2))
        limb(CGPoint(x: cx + 8, y: base + 12), CGPoint(x: cx + 16 + splay, y: base + 2))
        bodyShape(cx, base + 20, 34, 30)
        plainOval(cx, base + 14, 20, 14, cream)
        limb(CGPoint(x: cx - 7, y: base + 28), CGPoint(x: cx - 18, y: base + 42 + splay))
        limb(CGPoint(x: cx + 7, y: base + 28), CGPoint(x: cx + 18, y: base + 42 - splay))
        drawHead(at: CGPoint(x: cx, y: base + 46), scale: 1, earPerk: 1.2, happy: true)
    }

    /// Picked up: legs dangle, ears fold back.
    private func drawHeld() {
        let cx = bounds.midX, y = base + 40
        let sway = sin(phase * 3) * 3
        tail(from: CGPoint(x: cx - 12, y: y - 4), to: CGPoint(x: cx - 26 + sway, y: y - 28),
             c1: CGPoint(x: cx - 26, y: y - 2), c2: CGPoint(x: cx - 30, y: y - 18))
        for (i, dx) in [-13.0 as CGFloat, -5, 5, 13].enumerated() {
            let s = sin(phase * 3 + CGFloat(i) * 0.7) * 2.5
            limb(CGPoint(x: cx + dx * 0.6, y: y - 8), CGPoint(x: cx + dx + s, y: y - 26))
        }
        bodyShape(cx, y, 34, 30)
        plainOval(cx, y - 4, 20, 16, cream)
        drawHead(at: CGPoint(x: cx, y: y + 26), scale: 1, earPerk: 0.6)
    }

    // MARK: head

    private func drawHead(at c: CGPoint, scale s: CGFloat, earPerk: CGFloat,
                          asleep: Bool = false, happy: Bool = false) {
        if skin.crest == .ears {
            for dir in [-1.0 as CGFloat, 1.0] {
                let p = NSBezierPath(), bx = c.x + dir * 9 * s
                p.move(to: CGPoint(x: bx - 6 * s, y: c.y + 6 * s))
                p.line(to: CGPoint(x: bx + dir * 2 * s, y: c.y + (16 * earPerk + 6) * s))
                p.line(to: CGPoint(x: bx + 6 * s, y: c.y + 6 * s))
                p.close(); fillStroke(p, fur)
                let ip = NSBezierPath()
                ip.move(to: CGPoint(x: bx - 2.6 * s, y: c.y + 8 * s))
                ip.line(to: CGPoint(x: bx + dir * 1.2 * s, y: c.y + (13 * earPerk + 6) * s))
                ip.line(to: CGPoint(x: bx + 2.6 * s, y: c.y + 8 * s))
                ip.close(); pink.setFill(); ip.fill()
            }
        } else if skin.crest == .round {
            for dir in [-1.0 as CGFloat, 1.0] {    // panda: round ears on top
                let bx = c.x + dir * 11 * s
                let by = c.y + (9 + 3 * (earPerk - 1)) * s
                oval(bx, by, 15 * s, 15 * s, furDk)
            }
        } else if skin.crest == .floppy {
            for dir in [-1.0 as CGFloat, 1.0] {    // ears hanging beside the head
                let bx = c.x + dir * 14 * s
                let lift = (earPerk - 1) * 9 * s
                let ear = NSBezierPath(ovalIn: NSRect(x: bx - 6.5 * s, y: c.y - 15 * s + lift,
                                                      width: 13 * s, height: 26 * s))
                fillStroke(ear, furDk)
            }
        } else {
            for i in 0..<3 {                       // crest of plates along the skull
                let x = c.x + (CGFloat(i) - 1) * 8 * s
                let peak = (7 + CGFloat(2 - abs(i - 1)) * 3) * earPerk * s
                let sp = NSBezierPath()
                sp.move(to: CGPoint(x: x - 5 * s, y: c.y + 8 * s))
                sp.line(to: CGPoint(x: x, y: c.y + 8 * s + peak))
                sp.line(to: CGPoint(x: x + 5 * s, y: c.y + 8 * s))
                sp.close(); fillStroke(sp, furDk, 1.4)
            }
        }
        oval(c.x, c.y, 30 * s, 26 * s, fur)

        if skin.eyePatches {
            for dir in [-1.0 as CGFloat, 1.0] {
                let p = NSBezierPath(ovalIn: NSRect(x: c.x + dir * 6.5 * s - 7.5 * s,
                                                    y: c.y + 2 * s - 8.5 * s,
                                                    width: 15 * s, height: 17 * s))
                let t = NSAffineTransform()
                t.translateX(by: c.x + dir * 6.5 * s, yBy: c.y + 2 * s)
                t.rotate(byDegrees: dir * -14)
                t.translateX(by: -(c.x + dir * 6.5 * s), yBy: -(c.y + 2 * s))
                p.transform(using: t as AffineTransform)
                furDk.setFill(); p.fill()
            }
        }

        let open = (asleep || happy) ? 0 : max(0.08, 1 - blink)
        for dir in [-1.0 as CGFloat, 1.0] {
            let ex = c.x + dir * 6.5 * s, ey = c.y + 2 * s
            if open < 0.2 {
                let p = NSBezierPath()
                p.move(to: CGPoint(x: ex - 4 * s, y: ey))
                p.curve(to: CGPoint(x: ex + 4 * s, y: ey),
                        controlPoint1: CGPoint(x: ex - 1.5 * s, y: ey + 4 * s),
                        controlPoint2: CGPoint(x: ex + 1.5 * s, y: ey + 4 * s))
                ink.setStroke(); p.lineWidth = 1.8; p.lineCapStyle = .round; p.stroke()
            } else {
                plainOval(ex, ey, 8 * s, 9 * s * open, .white)
                let ring = NSBezierPath(ovalIn: NSRect(x: ex - 4 * s, y: ey - 4.5 * s * open,
                                                       width: 8 * s, height: 9 * s * open))
                ink.setStroke(); ring.lineWidth = 1.3; ring.stroke()
                plainOval(ex + eyeOffset.x * 1.8, ey + eyeOffset.y * 1.8 * open, 4.2 * s, 5.4 * s * open, ink)
                plainOval(ex + eyeOffset.x * 1.8 + 1.2, ey + eyeOffset.y * 1.8 * open + 1.6,
                          1.8 * s, 1.8 * s * open, .white)
            }
        }

        if skin.snout {                            // dog: muzzle patch + round nose
            plainOval(c.x, c.y - 4.6 * s, 18 * s, 12 * s, cream)
            oval(c.x, c.y - 2.4 * s, 9 * s, 6.4 * s, pink, 1.3)
        } else {
            let nose = NSBezierPath()
            nose.move(to: CGPoint(x: c.x - 2.4 * s, y: c.y - 3.4 * s))
            nose.line(to: CGPoint(x: c.x + 2.4 * s, y: c.y - 3.4 * s))
            nose.line(to: CGPoint(x: c.x, y: c.y - 6 * s)); nose.close()
            pink.setFill(); nose.fill()
        }
        let mouth = NSBezierPath()
        mouth.move(to: CGPoint(x: c.x, y: c.y - 6 * s))
        mouth.line(to: CGPoint(x: c.x, y: c.y - 7.6 * s))
        mouth.appendArc(withCenter: CGPoint(x: c.x - 2.6 * s, y: c.y - 7.6 * s),
                        radius: 2.6 * s, startAngle: 0, endAngle: -180, clockwise: true)
        mouth.move(to: CGPoint(x: c.x, y: c.y - 7.6 * s))
        mouth.appendArc(withCenter: CGPoint(x: c.x + 2.6 * s, y: c.y - 7.6 * s),
                        radius: 2.6 * s, startAngle: 180, endAngle: 0, clockwise: false)
        ink.setStroke(); mouth.lineWidth = 1.4; mouth.stroke()

        guard skin.whiskers else { return }
        ink.withAlphaComponent(0.75).setStroke()
        for dir in [-1.0 as CGFloat, 1.0] {
            for k in [-1.0 as CGFloat, 1.0] {
                let w = NSBezierPath()
                w.move(to: CGPoint(x: c.x + dir * 5 * s, y: c.y - 4 * s))
                w.line(to: CGPoint(x: c.x + dir * 17 * s, y: c.y - 4 * s + k * 3.4 * s))
                w.lineWidth = 1.1; w.lineCapStyle = .round; w.stroke()
            }
        }
    }

    // MARK: bubbles + labels

    private func bubble(_ rect: NSRect) {
        let b = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        fillStroke(b, NSColor(white: 1, alpha: 0.96), 1.4)
        oval(rect.minX + 10, rect.minY - 5, 7, 6, NSColor(white: 1, alpha: 0.96), 1.3)
        oval(rect.minX + 4, rect.minY - 11, 4.5, 4, NSColor(white: 1, alpha: 0.96), 1.2)
    }

    private func drawThoughtBubble() {
        let r = NSRect(x: bounds.midX + 6, y: base + 74, width: 46, height: 24)
        bubble(r)
        for i in 0..<3 {
            let t = sin(phase * 2.2 - CGFloat(i) * 0.8)
            let a = 0.35 + max(0, t) * 0.65
            plainOval(r.minX + 12 + CGFloat(i) * 11, r.midY, 6, 6, ink.withAlphaComponent(a))
        }
    }

    private func drawBangBubble() {
        let r = NSRect(x: bounds.midX + 6, y: base + 78, width: 26, height: 26)
        bubble(r)
        let s = 20 + sin(phase * 5) * 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s, weight: .heavy), .foregroundColor: warn]
        let str = NSString(string: "!")
        let sz = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: attrs)
    }

    private func drawSparkles() {
        for i in 0..<5 {
            let ang = CGFloat(i) * 1.25 + phase * 0.6
            let rad = 34 + sin(phase * 3 + CGFloat(i)) * 6
            let p = CGPoint(x: bounds.midX + cos(ang) * rad, y: base + 46 + sin(ang) * rad * 0.55)
            let a = 0.45 + 0.55 * abs(sin(phase * 3 + CGFloat(i)))
            let star = NSBezierPath()
            for k in 0..<4 {
                let t = CGFloat(k) * .pi / 2
                star.move(to: p)
                star.line(to: CGPoint(x: p.x + cos(t) * 5, y: p.y + sin(t) * 5))
            }
            NSColor(srgbRed: 1, green: 0.82, blue: 0.35, alpha: a).setStroke()
            star.lineWidth = 2; star.lineCapStyle = .round; star.stroke()
        }
    }

    private func drawPill(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: NSColor.white]
        let str = NSString(string: text)
        let sz = str.size(withAttributes: attrs)
        let r = NSRect(x: bounds.midX - sz.width / 2 - 7, y: 4, width: sz.width + 14, height: sz.height + 5)
        ink.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        str.draw(at: CGPoint(x: r.minX + 7, y: r.minY + 2.5), withAttributes: attrs)
    }

    private func drawZs() {
        let cx = bounds.midX + 22
        for i in 0..<3 {
            let t = (zPhase + CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9 + CGFloat(i) * 3, weight: .bold),
                .foregroundColor: NSColor(white: 0.32, alpha: (1 - t) * 0.85)]
            NSString(string: "z").draw(at: CGPoint(x: cx + t * 10, y: base + 40 + t * 28), withAttributes: attrs)
        }
    }
}

// MARK: - Offscreen pose render (verification / preview)

// MARK: - Host plugins (Claude Code, Codex, Gemini CLI, opencode)

/// One lifecycle event: what the agent calls it, what the pet calls it, and
/// the matcher to register (nil = none, which matches everything).
struct HookEvent {
    let host: String
    let pet: String
    let matcher: String?
    init(_ host: String, as pet: String? = nil, matcher: String? = nil) {
        self.host = host
        self.pet = pet ?? host
        self.matcher = matcher
    }
}

/// A coding agent whose lifecycle hooks can drive the pet.
///
/// Most agents take JSON config listing commands to run. opencode instead
/// loads JavaScript plugins, so it gets a generated plugin file.
struct HookHost {
    enum Kind {
        /// JSON config with a "hooks" object, as Claude Code, Codex and
        /// Gemini CLI all use.
        case json(files: [URL], events: [HookEvent], timeout: Int, supportsAsync: Bool)
        /// A JavaScript plugin file, written to `file`. `alternates` are other
        /// locations an older install may have used; they are cleaned up too.
        case plugin(file: URL, alternates: [URL])
    }

    let id: String
    let name: String
    /// Name of the config file inside a config folder.
    let fileName: String
    let kind: Kind

    var files: [URL] {
        switch kind {
        case .json(let files, _, _, _): return files
        case .plugin(let file, _):      return [file]
        }
    }

    var events: [HookEvent] {
        if case .json(_, let events, _, _) = kind { return events }
        return []
    }

    /// True when the agent appears to be installed for this user.
    var isPresent: Bool {
        switch kind {
        case .json(let files, _, _, _):
            return files.contains {
                FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path)
            }
        case .plugin(let file, _):
            // the plugin folder is ours to create; the agent's config root is
            // what says whether the agent itself is here
            let root = file.deletingLastPathComponent().deletingLastPathComponent()
            return FileManager.default.fileExists(atPath: root.path)
        }
    }

    /// Plugin hosts write the pet's state file themselves.
    var callsTheCLI: Bool { if case .json = kind { return true } else { return false } }

    static var defaultClaudeDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    }

    /// Other ~/.claude-* folders on this machine. Never touched automatically;
    /// reported by `pet plugin status` so an old install is not forgotten.
    static func otherClaudeDirs(besides managedPaths: Set<String>) -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory())) ?? []
        return entries.sorted()
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { home.appendingPathComponent($0).standardizedFileURL }
            .filter { url in
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return exists && isDir.boolValue && !managedPaths.contains(url.path)
            }
    }

    /// Same host, pointed at folders given with --path. A path ending in the
    /// host's file extension is taken as the config file itself.
    func targeting(_ paths: [URL]) -> HookHost {
        let resolved = paths.map { path -> URL in
            let ext = path.pathExtension.lowercased()
            return (ext == "json" || ext == "js") ? path : path.appendingPathComponent(fileName)
        }
        switch kind {
        case .json(_, let events, let timeout, let supportsAsync):
            return HookHost(id: id, name: name, fileName: fileName,
                            kind: .json(files: resolved, events: events,
                                        timeout: timeout, supportsAsync: supportsAsync))
        case .plugin(_, let alternates):
            return HookHost(id: id, name: name, fileName: fileName,
                            kind: .plugin(file: resolved[0], alternates: alternates))
        }
    }

    static var claude: HookHost {
        HookHost(id: "claude", name: "Claude Code", fileName: "settings.json",
                 kind: .json(
                    files: [defaultClaudeDir.appendingPathComponent("settings.json")],
                    events: [HookEvent("SessionStart"), HookEvent("UserPromptSubmit"),
                             HookEvent("PreToolUse", matcher: "*"),
                             HookEvent("PostToolUse", matcher: "*"),
                             HookEvent("Notification"), HookEvent("Stop"),
                             HookEvent("SessionEnd")],
                    timeout: 5, supportsAsync: true))
    }

    /// Codex keeps hooks in ~/.codex/hooks.json. Matchers there are regexes,
    /// so they are omitted, which matches every tool.
    static var codex: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        return HookHost(id: "codex", name: "Codex", fileName: "hooks.json",
                        kind: .json(
                            files: [dir.appendingPathComponent("hooks.json")],
                            events: [HookEvent("SessionStart"), HookEvent("UserPromptSubmit"),
                                     HookEvent("PreToolUse"), HookEvent("PostToolUse"),
                                     HookEvent("PermissionRequest", as: "Notification"),
                                     HookEvent("Stop"), HookEvent("SessionEnd")],
                            timeout: 5, supportsAsync: true))
    }

    /// Gemini CLI uses its own event vocabulary, its timeout is in
    /// milliseconds, and it has no async flag — hooks there block briefly.
    static var gemini: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini")
        return HookHost(id: "gemini", name: "Gemini CLI", fileName: "settings.json",
                        kind: .json(
                            files: [dir.appendingPathComponent("settings.json")],
                            events: [HookEvent("SessionStart"),
                                     HookEvent("BeforeAgent", as: "UserPromptSubmit"),
                                     HookEvent("BeforeTool", as: "PreToolUse"),
                                     HookEvent("AfterTool", as: "PostToolUse"),
                                     HookEvent("AfterAgent", as: "Stop"),
                                     HookEvent("Notification"), HookEvent("SessionEnd")],
                            timeout: 5000, supportsAsync: false))
    }

    /// opencode loads JavaScript plugins. Both plugin/ and plugins/ are read
    /// (verified against 1.18.x), so install into one and clean both.
    static var opencode: HookHost {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/opencode")
        return HookHost(id: "opencode", name: "opencode", fileName: "pet.js",
                        kind: .plugin(
                            file: dir.appendingPathComponent("plugin/pet.js"),
                            alternates: [dir.appendingPathComponent("plugins/pet.js")]))
    }

    static var all: [HookHost] { [.claude, .codex, .gemini, .opencode] }
    static func named(_ id: String) -> HookHost? { all.first { $0.id == id } }
}

/// The JavaScript plugin written into opencode's plugin folder. It writes the
/// pet's state file directly — no process to spawn per event.
enum OpencodePlugin {
    static var source: String {
        """
        // Desktop Pet — opencode plugin.
        //
        // Written by `pet plugin install opencode`. Reports what opencode is
        // doing to the pet by writing one line to its state file:
        //     EVENT|TOOL|EPOCH
        // Remove it with `pet plugin uninstall opencode`.

        import { writeFileSync, mkdirSync } from "fs"
        import { homedir } from "os"
        import { join } from "path"

        const dir = process.env.PET_CONFIG_DIR || join(homedir(), ".config", "pet")

        function record(event, tool = "") {
          try {
            mkdirSync(dir, { recursive: true })
            writeFileSync(join(dir, "state"),
                          `${event}|${tool}|${Math.floor(Date.now() / 1000)}\\n`)
          } catch (e) {
            // never let the pet interfere with a session
          }
        }

        // opencode passes (input, output); the tool name has moved around
        // between versions, so try the shapes it has used.
        function toolName(input) {
          return input?.tool ?? input?.name ?? input?.toolName ?? ""
        }

        export const DesktopPet = async () => ({
          "session.created":     async () => record("SessionStart"),
          "session.idle":        async () => record("Stop"),
          "permission.asked":    async () => record("Notification"),
          "tool.execute.before": async (input) => record("PreToolUse", toolName(input)),
          "tool.execute.after":  async (input) => record("PostToolUse", toolName(input)),
        })
        """
    }
}

enum HookPlugin {
    /// Claude runs the `pet` CLI directly — there is no generated script.
    static var command: String {
        let path = CLI.installedCommandPath
        return (path.contains(" ") ? "\"\(path)\"" : path) + " event"
    }

    /// Recognises our hook entries: the current CLI form, an install that
    /// lives somewhere else, and the pre-1.0 generated script.
    ///
    /// Deliberately strict. Matching loosely would make install and uninstall
    /// delete somebody else's hook — a command like `/opt/tools/snippet event
    /// PreToolUse` must not look like ours just because it ends in "pet".
    static func isOurCommand(_ command: String) -> Bool {
        if command.contains("pet-hook.sh") { return true }              // legacy

        let text = command.trimmingCharacters(in: .whitespaces)
        let executable: String
        if text.hasPrefix("\"") {                                       // quoted path
            let body = text.dropFirst()
            guard let end = body.firstIndex(of: "\"") else { return false }
            executable = String(body[body.startIndex..<end])
        } else {
            executable = String(text.split(separator: " ").first ?? "")
        }

        // The program itself must be the pet, and it must be the event subcommand.
        let name = URL(fileURLWithPath: executable).lastPathComponent
        guard name == "pet" || name == "Pet" else { return false }
        let arguments = text.dropFirst(text.hasPrefix("\"") ? executable.count + 2
                                                            : executable.count)
        return arguments.trimmingCharacters(in: .whitespaces).hasPrefix("event ")
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        let hooks = group["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { isOurCommand($0["command"] as? String ?? "") }
    }

    enum MergeResult { case changed(Int), unchanged, unreadable }

    /// Reconciles our entries in one config file and leaves the rest alone.
    static func merge(file url: URL, events: [HookEvent], timeout: Int,
                      supportsAsync: Bool, remove: Bool) -> MergeResult {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unreadable          // never clobber a file we cannot parse
            }
            root = parsed
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = 0

        for event in events {
            var list = hooks[event.host] as? [[String: Any]] ?? []
            let want = "\(command) \(event.pet)"

            if remove {
                let kept = list.filter { !isOurs($0) }
                if kept.count != list.count { changed += 1 }
                if kept.isEmpty { hooks.removeValue(forKey: event.host) } else { hooks[event.host] = kept }
                continue
            }

            // drop our entries that point elsewhere (an older install)
            list = list.filter { group in
                guard isOurs(group) else { return true }
                let correct = (group["hooks"] as? [[String: Any]] ?? [])
                    .contains { ($0["command"] as? String) == want }
                if !correct { changed += 1 }
                return correct
            }
            if !list.contains(where: isOurs) {
                var handler: [String: Any] = ["type": "command", "command": want,
                                              "timeout": timeout]
                if supportsAsync { handler["async"] = true }   // Gemini has no async flag
                var entry: [String: Any] = ["hooks": [handler]]
                if let matcher = event.matcher { entry["matcher"] = matcher }
                list.append(entry)
                changed += 1
            }
            hooks[event.host] = list
        }

        if remove && hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        guard changed > 0 else { return .unchanged }

        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak-pet")
            try? FileManager.default.removeItem(at: backup)     // keep the latest backup
            try? FileManager.default.copyItem(at: url, to: backup)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
        }
        guard let out = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return .unreadable
        }
        try? out.write(to: url)
        return .changed(changed)
    }

    static func registeredCount(in file: URL) -> Int {
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return 0 }
        return hooks.values.reduce(0) { total, value in
            total + ((value as? [[String: Any]] ?? []).filter(isOurs).count)
        }
    }

    static func isRegistered(_ host: HookHost) -> Bool {
        switch host.kind {
        case .json:
            return host.files.contains { registeredCount(in: $0) > 0 }
        case .plugin(let file, let alternates):
            return ([file] + alternates).contains { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    static var isRegisteredAnywhere: Bool { HookHost.all.contains(where: isRegistered) }

    static func apply(_ host: HookHost, remove: Bool) {
        print("\(host.name):")
        switch host.kind {
        case .json(let files, let events, let timeout, let supportsAsync):
            for file in files {
                let label = CLI.tilde(file.deletingLastPathComponent())
                if remove, !FileManager.default.fileExists(atPath: file.path) {
                    print("  ·  \(label) — nothing to remove")
                    continue
                }
                switch merge(file: file, events: events, timeout: timeout,
                             supportsAsync: supportsAsync, remove: remove) {
                case .unreadable:     print("  !  \(label) — \(file.lastPathComponent) unreadable, left untouched")
                case .unchanged:      print("  ·  \(label) already up to date")
                case .changed(let n): print("  ✓  \(label) — \(n) event(s) \(remove ? "removed" : "updated")")
                }
            }
        case .plugin(let file, let alternates):
            if remove {
                var removed = false
                for url in [file] + alternates where FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                    print("  ✓  removed \(CLI.tilde(url))")
                    removed = true
                }
                if !removed { print("  ·  nothing to remove") }
                return
            }
            // a stale copy in the other plugin folder would fire twice
            for url in alternates where FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                print("  ✓  removed duplicate \(CLI.tilde(url))")
            }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try OpencodePlugin.source.write(to: file, atomically: true, encoding: .utf8)
                print("  ✓  \(CLI.tilde(file))")
            } catch {
                print("  !  could not write \(CLI.tilde(file)): \(error.localizedDescription)")
            }
        }
    }

    static func install(_ hosts: [HookHost]) {
        try? FileManager.default.createDirectory(at: SkinStore.configDir,
                                                 withIntermediateDirectories: true)
        if hosts.contains(where: \.callsTheCLI) {
            print("hook command: \(command) <event>")
        }
        print("")
        for host in hosts { apply(host, remove: false) }
        cleanLegacy()
        print("")
        print("Start a new session in \(hosts.map(\.name).joined(separator: " / ")) — "
            + "the pet will start reacting.")
    }

    static func uninstall(_ hosts: [HookHost]) {
        for host in hosts { apply(host, remove: true) }
        cleanLegacy()
    }

    /// Earlier versions generated a shell script; the CLI replaces it.
    static func cleanLegacy() {
        let script = SkinStore.configDir.appendingPathComponent("pet-hook.sh")
        if FileManager.default.fileExists(atPath: script.path) {
            try? FileManager.default.removeItem(at: script)
            print("  ✓  removed the old \(CLI.tilde(script))")
        }
        let older = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/pet")
        if FileManager.default.fileExists(atPath: older.appendingPathComponent("pet-hook.sh").path) {
            try? FileManager.default.removeItem(at: older)
            print("  ✓  removed the old hook at ~/.claude/pet")
        }
    }

    static func status() {
        print("hook command: \(command) <event>   (opencode writes the state file directly)")
        for host in HookHost.all {
            print("")
            print("\(host.name)\(host.isPresent ? "" : "  (not installed)"):")
            switch host.kind {
            case .json(let files, _, _, _):
                for file in files {
                    let label = CLI.tilde(file.deletingLastPathComponent())
                    let n = registeredCount(in: file)
                    print("  \(label): \(n == 0 ? "not registered" : "\(n) hook entries")")
                }
            case .plugin(let file, let alternates):
                let installed = ([file] + alternates).filter {
                    FileManager.default.fileExists(atPath: $0.path)
                }
                let where_ = installed.isEmpty ? "not registered"
                                               : installed.map(CLI.tilde).joined(separator: ", ")
                print("  \(where_)")
            }
            if host.id == "claude" {
                let managed = Set(host.files.map { $0.deletingLastPathComponent().standardizedFileURL.path })
                let stray = HookHost.otherClaudeDirs(besides: managed).filter {
                    registeredCount(in: $0.appendingPathComponent(host.fileName)) > 0
                }
                for dir in stray {
                    print("  !  \(CLI.tilde(dir)) also has pet hooks")
                    print("     clean it with `pet plugin uninstall claude --path \(CLI.tilde(dir))`")
                }
            }
        }
    }
}

// MARK: - CLI

enum CLI {
    static func tilde(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(("pet: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }

    /// The bundle this binary belongs to (the CLI is usually a symlink into it).
    static var appURL: URL? {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let macos = exe.deletingLastPathComponent()
        if macos.lastPathComponent == "MacOS" {
            let app = macos.deletingLastPathComponent().deletingLastPathComponent()
            if app.pathExtension == "app" { return app }
        }
        for path in ["\(NSHomeDirectory())/Applications/Pet.app", "/Applications/Pet.app"] {
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Absolute path Claude should call: the installed `pet`, else this binary.
    static var installedCommandPath: String {
        for dir in ["/usr/local/bin", "\(NSHomeDirectory())/.local/bin"] {
            let link = dir + "/pet"
            if FileManager.default.fileExists(atPath: link) { return link }
        }
        return URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }

    /// Called by Claude Code hooks. Reads the hook payload on stdin and
    /// records one line of activity. Always exits 0 and never blocks a turn.
    static func event(_ name: String?) -> Never {
        guard let name else { exit(0) }
        var tool = ""
        if isatty(FileHandle.standardInput.fileDescriptor) == 0 {   // only when piped
            let data = FileHandle.standardInput.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = json["tool_name"] as? String {
                tool = value
            }
        }
        let dir = SkinStore.configDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "\(name)|\(tool)|\(Int(Date().timeIntervalSince1970))\n"
        try? line.write(to: dir.appendingPathComponent("state"), atomically: true, encoding: .utf8)
        exit(0)
    }

    static var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Prefs.domain)
    }

    static func help() {
        print("""
        pet — Desktop Pet

        USAGE
          pet <command> [arguments]

        APP
          status                 what the pet is doing right now
          start | stop | restart
          show | hide            show or hide the pet
          tray show | tray hide  show or hide the menu bar icon

        SKINS
          skins                  list installed skins
          skin <id>              switch skin
          skins dir              print the skins folder

        CONFIG
          config                 print the config folder and where it came from
          config set <path>      use a different config folder
          config reset           go back to ~/.config/pet

        AGENT PLUGIN
          plugin install [agent]   make the pet react to your coding agent
                                   agent = claude | codex | gemini | opencode
          plugin uninstall [agent] default: every agent found
          plugin status
          --path <dir>             a config folder other than the default;
                                   repeatable
          event <name>             record activity; this is what the hooks call

        OTHER
          render <file>          render every skin and pose to a PNG sheet
          icon [size] <file>     render the app icon
          uninstall [--all]      remove the app and this CLI (--all: config too)
          version | help
        """)
    }

    static func run(_ argv: [String]) -> Never {
        var args = Array(argv.dropFirst())
        let cmd = args.removeFirst()
        switch cmd {
        case "help", "--help", "-h": help()
        case "version", "--version": print("pet 1.0")
        case "status":               status()
        case "start":                start()
        case "stop":                 stop()
        case "restart":              stop(); Thread.sleep(forTimeInterval: 0.6); start()
        case "show":                 setHidden(false)
        case "hide":                 setHidden(true)
        case "tray":                 tray(args.first)
        case "skins":                args.first == "dir" ? print(SkinStore.userDir.path) : listSkins()
        case "skin":                 setSkin(args.first)
        case "config":               config(args)
        case "event":                event(args.first)
        case "plugin":               plugin(args)
        case "uninstall":            uninstall(all: args.contains("--all"))
        default: fail("unknown command \"\(cmd)\" — try: pet help")
        }
        exit(0)
    }

    // MARK: app

    static func status() {
        Prefs.refresh()
        let d = Prefs.store
        let live = (try? String(contentsOf: SkinStore.configDir.appendingPathComponent("runtime"),
                                encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRunning = !running.isEmpty
        print("app        : \(isRunning ? "running" : "not running")")
        if isRunning, let live { print("             \(live)") }
        print("config     : \(tilde(SkinStore.configDir))\(SkinStore.configDirIsFromEnvironment ? "  ($PET_CONFIG_DIR)" : SkinStore.isCustomConfigDir ? "  (custom)" : "")")
        let skins = SkinStore.load().skins
        print("skins      : \(skins.count) in \(tilde(SkinStore.userDir))")
        print("current    : \(d.string(forKey: "petSkin") ?? "tabby")")
        print("hidden     : \(d.bool(forKey: "petHidden") ? "yes" : "no")")
        print("chase      : \(d.bool(forKey: "petChase") ? "on" : "off")")
        print("menu bar   : \(d.bool(forKey: "petTrayHidden") ? "hidden" : "shown")")

        let state = SkinStore.configDir.appendingPathComponent("state")
        if let raw = try? String(contentsOf: state, encoding: .utf8) {
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
            if parts.count >= 3, let ts = Double(parts[2]) {
                let age = Int(Date().timeIntervalSince1970 - ts)
                let tool = parts[1].isEmpty ? "" : " (\(parts[1]))"
                print("last event : \(parts[0])\(tool), \(age)s ago")
            }
        } else {
            print("last event : none — run `pet plugin install` to react to Claude Code")
        }
    }

    static func start() {
        guard let app = appURL else { fail("Pet.app not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [app.path]
        try? p.run()
        p.waitUntilExit()
        print("started \(tilde(app))")
    }

    static func stop() {
        let apps = running
        guard !apps.isEmpty else { print("not running"); return }
        apps.forEach { $0.terminate() }
        print("stopped")
    }

    static func tray(_ action: String?) {
        Prefs.refresh()
        switch action {
        case "show", "hide":
            let hide = action == "hide"
            Prefs.store.set(hide, forKey: "petTrayHidden")
            Prefs.store.synchronize()
            Prefs.notifyRunningApp()
            print(hide ? "menu bar icon hidden — `pet tray show` brings it back"
                       : "menu bar icon shown")
        case nil, "status":
            print(Prefs.store.bool(forKey: "petTrayHidden") ? "hidden" : "shown")
        default:
            fail("usage: pet tray [show | hide]")
        }
    }

    static func setHidden(_ value: Bool) {
        Prefs.store.set(value, forKey: "petHidden")
        Prefs.store.synchronize()
        Prefs.notifyRunningApp()
        print(value ? "pet hidden" : "pet shown")
    }

    // MARK: skins

    static func listSkins() {
        Prefs.refresh()
        let current = Prefs.store.string(forKey: "petSkin") ?? "tabby"
        let result = SkinStore.load()
        for skin in result.skins {
            print("\(skin.id == current ? " * " : "   ")\(skin.id.padding(toLength: max(10, skin.id.count + 1), withPad: " ", startingAt: 0))\(skin.name)")
        }
        for error in result.errors { print("  !  \(error)") }
    }

    static func setSkin(_ id: String?) {
        guard let id else { fail("usage: pet skin <id>   (see: pet skins)") }
        let skins = SkinStore.load().skins
        guard skins.contains(where: { $0.id == id }) else {
            fail("no skin \"\(id)\" — available: " + skins.map(\.id).joined(separator: ", "))
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

    // MARK: plugin

    /// `pet plugin install [claude|codex] [--path <dir>]…`
    /// With no agent, every agent that is actually installed for this user.
    /// With no --path, each agent's default config folder.
    static func hosts(_ args: [String]) -> [HookHost] {
        var paths: [URL] = []
        var agent: String?
        var rest = Array(args.dropFirst())          // drop install/uninstall
        while let arg = rest.first {
            rest.removeFirst()
            if arg == "--path" || arg == "-p" {
                guard let value = rest.first else { fail("--path needs a folder") }
                rest.removeFirst()
                paths.append(SkinStore.expand(value).standardizedFileURL)
            } else if arg.hasPrefix("--path=") {
                paths.append(SkinStore.expand(String(arg.dropFirst(7))).standardizedFileURL)
            } else if arg.hasPrefix("-") {
                fail("unknown option \"\(arg)\"")
            } else if agent == nil {
                agent = arg.lowercased()
            } else {
                fail("unexpected argument \"\(arg)\"")
            }
        }

        var chosen: [HookHost]
        if let agent {
            guard let host = HookHost.named(agent) else {
                fail("unknown agent \"\(agent)\" — use claude or codex")
            }
            chosen = [host]
        } else {
            guard paths.isEmpty else { fail("--path needs an agent, e.g. pet plugin install claude --path <dir>") }
            chosen = HookHost.all.filter(\.isPresent)
            if chosen.isEmpty {
                fail("no supported agent found (looked for ~/.claude and ~/.codex)")
            }
        }
        return paths.isEmpty ? chosen : chosen.map { $0.targeting(paths) }
    }

    static func plugin(_ args: [String]) {
        switch args.first {
        case "install":
            let chosen = hosts(args)
            print("Installing the pet plugin for \(chosen.map(\.name).joined(separator: " and "))…")
            HookPlugin.install(chosen)
        case "uninstall":
            let chosen = args.count > 1 ? hosts(args) : HookHost.all
            print("Removing the pet plugin…")
            HookPlugin.uninstall(chosen)
        case "status":
            HookPlugin.status()
        default:
            fail("usage: pet plugin [install | uninstall | status] [claude | codex] [--path <dir>]")
        }
    }

    // MARK: uninstall

    static func uninstall(all: Bool) {
        running.forEach { $0.terminate() }
        if HookPlugin.isRegisteredAnywhere {
            print("Removing the pet plugin…")
            HookPlugin.uninstall(HookHost.all)
        }
        if let app = appURL {
            try? FileManager.default.removeItem(at: app)
            print("  ✓  removed \(tilde(app))")
        }
        for dir in ["/usr/local/bin", "\(NSHomeDirectory())/.local/bin"] {
            let link = URL(fileURLWithPath: dir).appendingPathComponent("pet")
            if FileManager.default.fileExists(atPath: link.path) {
                try? FileManager.default.removeItem(at: link)
                print("  ✓  removed \(tilde(link))")
            }
        }
        if all {
            try? FileManager.default.removeItem(at: SkinStore.configDir)
            print("  ✓  removed \(tilde(SkinStore.configDir)) (skins and settings)")
        } else {
            print("")
            print("Your skins in \(tilde(SkinStore.userDir)) were left in place.")
        }
    }
}

// Choose between the CLI and the app.
//
//   pet <command> …   CLI, including -h/--help/--version
//   pet render|icon   fall through to the render blocks below
//   pet               in a terminal: help. Launched by Finder/open: the pet.
//
// macOS can append a -psn_… process-serial-number argument when launching a
// bundle, so it is ignored when deciding.
let petArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
let renderCommands: Set<String> = ["render", "icon", "--render", "--icon"]

if let first = petArgs.first {
    if !renderCommands.contains(first) {
        CLI.run([CommandLine.arguments[0]] + petArgs)
    }
} else if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent != "Pet" {
    // Invoked as `pet` with no arguments: show help. Only the bundle's own
    // executable (Contents/MacOS/Pet, how Finder and `open` launch it) starts
    // the pet itself — no guessing from pipes or terminals.
    CLI.help()
    exit(0)
}

// MARK: - App icon render (`--icon [size] out.png`)

if petArgs.first == "icon" || CommandLine.arguments.contains("--icon") {
    guard let out = petArgs.last, out.lowercased().hasSuffix(".png"), out != petArgs.first else {
        CLI.fail("usage: pet icon [size] <file.png>")
    }
    _ = NSApplication.shared
    let side = CGFloat(CommandLine.arguments.compactMap { Int($0) }.first ?? 1024)

    // The pet is captured as PDF so it stays sharp at any icon size.
    let view = PetView(frame: NSRect(x: 0, y: 0, width: 170, height: 165))
    view.skin = SkinStore.embeddedSkins.first { $0.id == "tabby" } ?? .fallback
    view.pose = .sitting
    view.phase = 0.8
    view.eyeOffset = CGPoint(x: 0.25, y: 0.1)
    let pdf = NSImage(data: view.dataWithPDF(inside: view.bounds))!

    // Draw into an explicit bitmap: lockFocus() would follow the display's
    // backing scale and silently produce a 2x image.
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = side * 0.098                            // macOS icon safe area
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = NSBezierPath(roundedRect: plate,
                             xRadius: plate.width * 0.2237, yRadius: plate.width * 0.2237)
    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.30, blue: 0.37, alpha: 1),
                        NSColor(srgbRed: 0.10, green: 0.14, blue: 0.19, alpha: 1)])!
        .draw(in: shape, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()                                     // nothing spills off the plate

    // soft radial warmth behind the pet, not a visible disc
    let centre = CGPoint(x: side * 0.5, y: side * 0.46)
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.84, blue: 0.58, alpha: 0.18),
                        NSColor(srgbRed: 1, green: 0.84, blue: 0.58, alpha: 0)])!
        .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: side * 0.40, options: [])

    // Place the cat: its body centre sits at (85, 54) inside the 170x165 view.
    // Scale so it fills most of the plate, then anchor that point on the centre.
    let w = side * 1.42, h = w * 165 / 170
    pdf.draw(in: NSRect(x: side * 0.5 - (85.0 / 170) * w,
                        y: side * 0.495 - (54.0 / 165) * h,
                        width: w, height: h),
             from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 1, alpha: 0.12).setStroke()          // rim light
    shape.lineWidth = side * 0.005
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()

    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: out))
    exit(0)
}

if petArgs.first == "render" || CommandLine.arguments.contains("--render") {
    guard let out = petArgs.last, out.lowercased().hasSuffix(".png"), out != petArgs.first else {
        CLI.fail("usage: pet render <file.png>")
    }
    _ = NSApplication.shared
    let specs: [(Pose, String?)] = [(.thinking, "thinking"), (.working, "Edit"), (.alert, "needs you"),
                                    (.celebrate, "done"), (.sitting, "held"), (.sleeping, nil)]
    let loaded = SkinStore.load().skins
    let w = 170, h = 165, rows = loaded.count
    let sheet = NSImage(size: NSSize(width: w * specs.count, height: h * rows))
    sheet.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: w * specs.count, height: h * rows).fill()
    for (r, sk) in loaded.enumerated() {
        for (i, spec) in specs.enumerated() {
            let v = PetView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            v.skin = sk
            v.pose = spec.0; v.label = spec.1; v.phase = 0.8; v.zPhase = 0.15
            v.eyeOffset = CGPoint(x: 0.5, y: 0.2)
            if spec.0 == .celebrate { v.hop = 10 }
            if spec.1 == "held" { v.held = true; v.label = nil }
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            rep.draw(in: NSRect(x: CGFloat(i * w), y: CGFloat((rows - 1 - r) * h),
                                width: CGFloat(w), height: CGFloat(h)))
        }
    }
    sheet.unlockFocus()
    let png = NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: out))
    exit(0)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let size = NSSize(width: 170, height: 165)
    var window: NSWindow!
    var view: PetView!
    var statusItem: NSStatusItem?
    var trayHidden = false             // menu bar icon hidden; CLI brings it back
    var timer: Timer?

    /// Activity file the pet reacts to: one line, EVENT|TOOL|EPOCH.
    /// Anything can write it — the Claude Code plugin is just one producer.
    var stateURL: URL { SkinStore.configDir.appendingPathComponent("state") }
    var lastStamp: TimeInterval = 0
    var event = "", tool = "", lastTool = ""
    var eventAge: TimeInterval = 9999
    var idleSince = Date()
    var pos = CGPoint.zero
    var chaseWhenIdle = false
    var dragging = false
    var isActive = false               // Claude is thinking / running a tool
    var hidden = false                 // pet hidden from screen via the menu
    var skins: [Skin] = []
    var skinErrors: [String] = []
    var skinMenu = NSMenu()
    let mainMenu = NSMenu()
    var statusRow: NSMenuItem!
    var visItem: NSMenuItem!
    var chaseItem: NSMenuItem!
    var flashText = ""                 // brief pill message after a toggle
    var flashUntil = Date.distantPast
    var savedPos = CGPoint.zero        // last position written to preferences
    var blinkTimer = 60
    var tick = 0
    let fps: Double = 30

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hidden = Prefs.store.bool(forKey: "petHidden")   // before the window is shown
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        view = PetView(frame: NSRect(origin: .zero, size: size))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = view
        if !hidden { window.orderFrontRegardless() }

        let d = Prefs.store
        chaseWhenIdle = d.bool(forKey: "petChase")
        reloadSkins()
        let wanted = d.string(forKey: "petSkin") ?? "tabby"
        view.skin = skins.first { $0.id == wanted } ?? skins[0]
        if d.object(forKey: "petPosX") != nil {
            pos = CGPoint(x: d.double(forKey: "petPosX"), y: d.double(forKey: "petPosY"))
        } else {
            let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            pos = CGPoint(x: f.midX, y: f.midY - size.height / 2)   // centre on first run
        }
        pos = clampToScreen(pos)
        savePos(force: true)
        view.dragBegin = { [weak self] in self?.dragging = true }
        view.dragMove  = { [weak self] origin in
            guard let self else { return }
            self.pos = CGPoint(x: origin.x + self.size.width / 2, y: origin.y)
            self.place()
        }
        view.dragEnd   = { [weak self] in self?.endDrag() }
        view.doubleClick = { [weak self] in self?.toggleChase() }
        place()

        trayHidden = Prefs.store.bool(forKey: "petTrayHidden")
        if !trayHidden { showTray() }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reloadFromPreferences),
            name: Notification.Name(Prefs.reloadNotification), object: nil)
        writeRuntime()

        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer!, forMode: .common)
    }

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

        let quit = NSMenuItem(title: "Quit Pet", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        mainMenu.addItem(quit)

        statusItem?.menu = mainMenu
    }

    /// Cheap: only the values that change while the app runs.
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
        case .celebrate: return "Just finished"
        case .sleeping:  return "Asleep"
        default:         return "Idle"
        }
    }

    func reloadSkins() {
        let result = SkinStore.load()
        skins = result.skins
        skinErrors = result.errors
        // keep showing the current skin if its file is still there, else fall back
        view.skin = skins.first { $0.id == view.skin.id } ?? skins[0]
    }

    /// Rebuilt on every open so skins added to the folder appear without a restart.
    func populateSkinMenu() {
        skinMenu.removeAllItems()
        for (i, sk) in skins.enumerated() {
            let it = NSMenuItem(title: sk.name, action: #selector(setSkin(_:)), keyEquivalent: "")
            it.target = self; it.tag = i
            it.state = sk.id == view.skin.id ? .on : .off
            skinMenu.addItem(it)
        }
        for err in skinErrors {
            let it = NSMenuItem(title: "⚠ \(err)", action: nil, keyEquivalent: "")
            it.isEnabled = false
            skinMenu.addItem(it)
        }
        skinMenu.addItem(.separator())
        for (title, sel) in [("Import Skin…", #selector(importSkin)),
                             ("Export Current Skin…", #selector(exportSkin))] {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            skinMenu.addItem(it)
        }

        skinMenu.addItem(.separator())
        let where_ = NSMenuItem(title: "Skins: \(Self.tildePath(SkinStore.userDir))",
                                action: nil, keyEquivalent: "")
        where_.isEnabled = false
        skinMenu.addItem(where_)

        var tail: [(String, Selector)] = [("Open Skins Folder", #selector(openSkinsFolder)),
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

    @objc func reloadSkinsMenu() { reloadSkins(); populateSkinMenu(); flash("skins reloaded") }

    @objc func openSkinsFolder() {
        SkinStore.seedIfEmpty()
        NSWorkspace.shared.open(SkinStore.userDir)
    }

    @objc func importSkin() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Import Skin"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        var types: [UTType] = [.json]
        if let t = UTType(filenameExtension: "petskin") { types.append(t) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return }

        var imported: Skin?
        for src in panel.urls {
            do {
                let skin = try Skin(contentsOf: src)       // validate before copying
                let dest = SkinStore.userDir.appendingPathComponent(src.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)
                imported = skin
            } catch {
                alert("Could not import \(src.lastPathComponent)", error.localizedDescription)
            }
        }
        reloadSkins()
        if let skin = imported, let match = skins.first(where: { $0.id == skin.id }) {
            apply(match)
        }
        populateSkinMenu()
    }

    @objc func exportSkin() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Export Skin"
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

    func apply(_ sk: Skin) {
        view.skin = sk
        defer { writeRuntime() }
        Prefs.store.set(sk.id, forKey: "petSkin")
        flash(sk.name.lowercased())
        view.needsDisplay = true
    }

    @objc func setSkin(_ item: NSMenuItem) {
        guard item.tag < skins.count else { return }
        let sk = skins[item.tag]
        apply(sk)
        populateSkinMenu()
    }

    func showTray() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐈"
        statusItem = item
        buildMenu()
    }

    func removeTray() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    @objc func hideTray() {
        trayHidden = true
        Prefs.store.set(true, forKey: "petTrayHidden")
        removeTray()
        writeRuntime()
        // This menu was the only way back, so say how to return.
        let alert = NSAlert()
        alert.messageText = "Menu bar icon hidden"
        alert.informativeText = "The pet keeps running. To bring the icon back, "
                              + "run this in Terminal:\n\n    pet tray show"
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func toggleHidden() {
        hidden.toggle()
        Prefs.store.set(hidden, forKey: "petHidden")
        if hidden {
            window.orderOut(nil)
        } else {
            place()
            window.orderFrontRegardless()
        }
        writeRuntime()
        refreshMenu()
    }

    @objc func toggleChase() {
        chaseWhenIdle.toggle()
        Prefs.store.set(chaseWhenIdle, forKey: "petChase")
        flashText = chaseWhenIdle ? "chase on" : "chase off"
        flashUntil = Date().addingTimeInterval(1.6)
        refreshMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }

    /// What the running app is actually doing, for `pet status`.
    func writeRuntime() {
        let dir = SkinStore.configDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "pid=\(ProcessInfo.processInfo.processIdentifier) skin=\(view.skin.id) "
                 + "hidden=\(hidden ? 1 : 0) chase=\(chaseWhenIdle ? 1 : 0) "
                 + "tray=\(trayHidden ? "hidden" : "shown")\n"
        try? line.write(to: dir.appendingPathComponent("runtime"), atomically: true, encoding: .utf8)
    }

    /// Re-read preferences after the CLI changed them.
    @objc func reloadFromPreferences() {
        Prefs.refresh()
        let d = Prefs.store
        let wantHidden = d.bool(forKey: "petHidden")
        if wantHidden != hidden {
            hidden = wantHidden
            if hidden { window.orderOut(nil) } else { place(); window.orderFrontRegardless() }
        }
        chaseWhenIdle = d.bool(forKey: "petChase")
        let wantTrayHidden = d.bool(forKey: "petTrayHidden")
        if wantTrayHidden != trayHidden {
            trayHidden = wantTrayHidden
            if trayHidden { removeTray() } else { showTray() }
        }
        reloadSkins()
        if let id = d.string(forKey: "petSkin"), let sk = skins.first(where: { $0.id == id }) {
            view.skin = sk
        }
        populateSkinMenu()
        refreshMenu()
        view.needsDisplay = true
        writeRuntime()
    }

    // MARK: placement

    func endDrag() {
        dragging = false
        pos = clampToScreen(pos)
        savePos()
        place()
        refreshMenu()
    }

    /// Remember where the pet is so it comes back there next launch.
    func savePos(force: Bool = false) {
        guard force || hypot(pos.x - savedPos.x, pos.y - savedPos.y) > 1 else { return }
        savedPos = pos
        let d = Prefs.store
        d.set(Double(pos.x), forKey: "petPosX")
        d.set(Double(pos.y), forKey: "petPosY")
    }

    func applicationWillTerminate(_ n: Notification) { savePos() }

    /// Keep the pet reachable: never let a drop land it off every screen.
    func clampToScreen(_ p: CGPoint) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        return CGPoint(x: min(max(p.x, f.minX + 50), f.maxX - 50),
                       y: min(max(p.y, f.minY + 4), f.maxY - size.height))
    }

    func place() { window.setFrameOrigin(NSPoint(x: pos.x - size.width / 2, y: pos.y)) }

    // MARK: state file

    func readState() {
        guard let raw = try? String(contentsOf: stateURL, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard parts.count >= 3, let ts = TimeInterval(parts[2]) else { return }
        let newEvent = parts[0], newTool = parts[1]
        if ts != lastStamp || newEvent != event {
            if ts != lastStamp { idleSince = Date() }
            lastStamp = ts; event = newEvent; tool = newTool
            if !newTool.isEmpty { lastTool = newTool }
        }
        eventAge = Date().timeIntervalSince1970 - ts
    }

    /// Map the Claude Code event to a pose.
    func updatePose() {
        let quiet = Date().timeIntervalSince(idleSince)
        let stale = eventAge > 90

        func idlePose() {
            view.label = nil
            if quiet > 25 { view.pose = .sleeping; view.zPhase += 0.006 }
            else if quiet > 10 && Int(quiet) % 6 < 2 { view.pose = .grooming }
            else { view.pose = .sitting }
        }

        switch event {
        case "Notification" where !stale, "PermissionRequest" where !stale:
            view.pose = .alert; view.label = "needs you"
        case "PreToolUse" where !stale:
            view.pose = .working; view.label = lastTool.isEmpty ? "working" : lastTool
        case "PostToolUse", "UserPromptSubmit":
            if stale { idlePose() } else { view.pose = .thinking; view.label = "thinking" }
        case "Stop" where eventAge < 2.4:
            view.pose = .celebrate; view.label = "done"
        default:
            idlePose()
        }
    }

    // MARK: frame

    func step() {
        tick += 1

        if hidden {                      // still follow Claude so the menu stays useful
            if tick % 3 == 0 { readState() } else { eventAge += 1 / fps }
            updatePose()
            isActive = [.working, .thinking, .alert, .celebrate].contains(view.pose)
            return
        }

        let mouseNow = NSEvent.mouseLocation

        // Per-pixel click-through: the window takes the mouse whenever the
        // cursor is over the cat itself, so it can always be grabbed or
        // double-clicked; everywhere else clicks pass through.
        // Never re-evaluate mid-drag: a fast drag can outrun the window and
        // would otherwise make it click-through, dropping the cat.
        if !dragging {
            let local = NSPoint(x: mouseNow.x - window.frame.minX, y: mouseNow.y - window.frame.minY)
            let grabbable = view.grabRect.contains(local)
            if window.ignoresMouseEvents == grabbable { window.ignoresMouseEvents = !grabbable }
        }

        if dragging {                    // user is holding it: no autonomy
            view.phase += 0.3
            view.needsDisplay = true
            return
        }

        if tick % 3 == 0 { readState() } else { eventAge += 1 / fps }
        updatePose()

        let active = [.working, .thinking, .alert, .celebrate].contains(view.pose)
        isActive = active
        if Date() < flashUntil { view.label = flashText }
        view.phase += active ? 0.3 : 0.07
        view.hop = view.pose == .celebrate ? abs(sin(view.phase * 1.9)) * 16 : 0

        // The pet has no home: it stays wherever it was last left, and only
        // walks when chasing is on and Claude is idle.
        var target = pos
        let mouse = NSEvent.mouseLocation
        if chaseWhenIdle && !active {
            let m = CGPoint(x: mouse.x, y: mouse.y - 40)
            if hypot(m.x - pos.x, m.y - pos.y) > 46 { target = m }
        }
        let dx = target.x - pos.x, dy = target.y - pos.y, dist = hypot(dx, dy)
        if dist > 2 {
            let speed = min(3 + dist * 0.07, 11)
            pos = CGPoint(x: pos.x + dx / dist * speed, y: pos.y + dy / dist * speed)
            if !active {
                view.pose = .running
                view.label = nil
                view.phase += 0.32
                if abs(dx) > 2 { view.facingRight = dx > 0 }
            }
        } else if !active {
            view.facingRight = mouse.x > pos.x
        } else {
            view.facingRight = true            // face the user while busy
        }

        let ex = max(-1, min(1, (mouse.x - pos.x) / 130))
        let ey = max(-1, min(1, (mouse.y - pos.y - 60) / 130))
        view.eyeOffset = CGPoint(x: ex, y: ey)

        blinkTimer -= 1
        if blinkTimer <= 0 {
            view.blink = min(1, view.blink + 0.34)
            if view.blink >= 1 { blinkTimer = Int.random(in: 60...220); view.blink = 0 }
        }

        place()
        view.needsDisplay = true
        if tick % 150 == 0 { savePos() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
