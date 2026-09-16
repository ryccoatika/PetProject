//  Renderers.swift
//  Desktop Pet
//
//  Offscreen renders used by the build and for checking drawing changes:
//  the app icon, the disk image background, and contact sheets of every
//  skin, pose and sprite track.

import Cocoa

enum Renderers {

    /// The disk image background, drawn from the same art as the pet.
    static func dmgBackground(to out: String) {
        let w: CGFloat = 600, h: CGFloat = 400
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        NSGradient(colors: [
            NSColor(srgbRed: 0.25, green: 0.31, blue: 0.38, alpha: 1),
            NSColor(srgbRed: 0.11, green: 0.15, blue: 0.20, alpha: 1),
        ])!
        .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

        // the pet, drawn small beside the title
        let pet = PetView(frame: NSRect(x: 0, y: 0, width: 170, height: 165))
        pet.skin = SkinStore.embeddedSkins.first { $0.id == "tabby" } ?? .fallback
        pet.pose = .sitting
        pet.phase = 0.8
        let pdf = NSImage(data: pet.dataWithPDF(inside: pet.bounds))!
        pdf.draw(
            in: NSRect(x: w / 2 - 120, y: h - 132, width: 120, height: 116),
            from: .zero, operation: .sourceOver, fraction: 1)

        let title: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subtitle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.65),
        ]
        NSString(string: "Desktop Pet").draw(
            at: NSPoint(x: w / 2 + 10, y: h - 96), withAttributes: title)
        let hint = NSString(string: "Drag the pet into your Applications folder")
        let hintSize = hint.size(withAttributes: subtitle)
        hint.draw(at: NSPoint(x: (w - hintSize.width) / 2, y: h - 150), withAttributes: subtitle)

        // arrow between the two icon positions (icons sit at y ≈ 210 from the top)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 238, y: 168))
        arrow.line(to: NSPoint(x: 362, y: 168))
        arrow.lineWidth = 5
        arrow.lineCapStyle = .round
        NSColor(white: 1, alpha: 0.45).setStroke()
        arrow.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 372, y: 168))
        head.line(to: NSPoint(x: 350, y: 181))
        head.line(to: NSPoint(x: 350, y: 155))
        head.close()
        NSColor(white: 1, alpha: 0.45).setFill()
        head.fill()

        let caption: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.45),
        ]
        let note = NSString(string: "the  pet  command is added automatically on first launch")
        let noteSize = note.size(withAttributes: caption)
        note.draw(at: NSPoint(x: (w - noteSize.width) / 2, y: 26), withAttributes: caption)

        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
    }

    /// The app icon, at any size.
    static func appIcon(size: Int, to out: String) {
        let side = CGFloat(size)

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

        let inset = side * 0.098  // macOS icon safe area
        let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        let shape = NSBezierPath(
            roundedRect: plate,
            xRadius: plate.width * 0.2237, yRadius: plate.width * 0.2237)
        NSGradient(colors: [
            NSColor(srgbRed: 0.24, green: 0.30, blue: 0.37, alpha: 1),
            NSColor(srgbRed: 0.10, green: 0.14, blue: 0.19, alpha: 1),
        ])!
        .draw(in: shape, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()  // nothing spills off the plate

        // soft radial warmth behind the pet, not a visible disc
        let centre = CGPoint(x: side * 0.5, y: side * 0.46)
        NSGradient(colors: [
            NSColor(srgbRed: 1, green: 0.84, blue: 0.58, alpha: 0.18),
            NSColor(srgbRed: 1, green: 0.84, blue: 0.58, alpha: 0),
        ])!
        .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: side * 0.40, options: [])

        // Place the cat: its body centre sits at (85, 54) inside the 170x165 view.
        // Scale so it fills most of the plate, then anchor that point on the centre.
        let w = side * 1.42, h = w * 165 / 170
        pdf.draw(
            in: NSRect(
                x: side * 0.5 - (85.0 / 170) * w,
                y: side * 0.495 - (54.0 / 165) * h,
                width: w, height: h),
            from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: 0.12).setStroke()  // rim light
        shape.lineWidth = side * 0.005
        shape.stroke()
        NSGraphicsContext.restoreGraphicsState()

        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
    }

    /// Every skin against every pose, and a row per sprite pack. Pass
    /// `tracks: true` for one column per atlas track instead.
    static func contactSheet(to out: String, tracks: Bool) {
        let specs: [(Pose, String?)] = [
            (.thinking, "thinking"), (.working, "Edit"), (.alert, "needs you"),
            (.celebrate, "done"), (.sitting, "held"), (.sleeping, nil),
            (.waving, nil), (.angry, nil),
        ]
        let loaded = SkinStore.load().skins
        let pets = SpriteStore.load()
        let w = 170, h = 165, rows = loaded.count + pets.count
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
                rep.draw(
                    in: NSRect(
                        x: CGFloat(i * w),
                        y: CGFloat((rows - 1 - r) * h),
                        width: CGFloat(w), height: CGFloat(h)))
            }
        }
        // every atlas track, so a pack can be checked at a glance
        if tracks {
            let all = SpritePet.Track.allCases
            let tw = 150, th = 190
            let strip = NSImage(size: NSSize(width: tw * all.count, height: th * pets.count))
            strip.lockFocus()
            NSColor(white: 0.15, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: tw * all.count, height: th * pets.count).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            for (r, pet) in pets.enumerated() {
                for (i, track) in all.enumerated() {
                    let box = NSRect(
                        x: CGFloat(i * tw), y: CGFloat((pets.count - 1 - r) * th) + 18,
                        width: CGFloat(tw), height: CGFloat(th - 34))
                    pet.draw(track: track, frame: 1, in: box)
                    NSString(string: "\(track.rawValue) \(track.label)")
                        .draw(
                            at: NSPoint(
                                x: CGFloat(i * tw) + 6,
                                y: CGFloat((pets.count - 1 - r) * th) + 4),
                            withAttributes: attrs)
                }
            }
            strip.unlockFocus()
            let png = NSBitmapImageRep(data: strip.tiffRepresentation!)!
                .representation(using: .png, properties: [:])!
            try! png.write(to: URL(fileURLWithPath: out))
            return
        }

        // sprite pets get a row each, using the same pose sequence
        for (r, pet) in pets.enumerated() {
            for (i, spec) in specs.enumerated() {
                let v = PetView(frame: NSRect(x: 0, y: 0, width: w, height: h))
                v.sprite = pet
                v.pose = spec.0; v.label = spec.1; v.spriteFrame = 1
                if spec.1 == "held" { v.held = true; v.label = nil; v.pose = .running }
                let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                v.cacheDisplay(in: v.bounds, to: rep)
                rep.draw(
                    in: NSRect(
                        x: CGFloat(i * w),
                        y: CGFloat((pets.count - 1 - r) * h),
                        width: CGFloat(w), height: CGFloat(h)))
            }
        }
        sheet.unlockFocus()
        let png = NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(
            using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: out))
    }
}
