//  PetView+Art.swift
//  Desktop Pet
//
//  How each pose is drawn, plus the head, bubbles and labels.

import Cocoa

extension PetView {

    // MARK: poses

    func drawRunning() {
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

    func stripes(cx: CGFloat, y: CGFloat) {
        guard skin.stripes else { return }
        furDk.setFill()
        for i in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: cx + CGFloat(i) * 9, y: y, width: 4, height: 9)).fill()
        }
    }

    /// Torso. Spiked skins get a row of plates poking out behind it.
    func bodyShape(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) {
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

    func drawSitting(grooming: Bool, tailFlick: Bool = false) {
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

    func drawSleeping() {
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
    func drawWorking() {
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

    func drawAlertPose() {
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

    func drawCelebrate() {
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
    func drawHeld() {
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

    func drawHead(at c: CGPoint, scale s: CGFloat, earPerk: CGFloat,
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

    func bubble(_ rect: NSRect) {
        let b = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        fillStroke(b, NSColor(white: 1, alpha: 0.96), 1.4)
        oval(rect.minX + 10, rect.minY - 5, 7, 6, NSColor(white: 1, alpha: 0.96), 1.3)
        oval(rect.minX + 4, rect.minY - 11, 4.5, 4, NSColor(white: 1, alpha: 0.96), 1.2)
    }

    func drawThoughtBubble() {
        let r = NSRect(x: bounds.midX + 6, y: base + 74, width: 46, height: 24)
        bubble(r)
        for i in 0..<3 {
            let t = sin(phase * 2.2 - CGFloat(i) * 0.8)
            let a = 0.35 + max(0, t) * 0.65
            plainOval(r.minX + 12 + CGFloat(i) * 11, r.midY, 6, 6, ink.withAlphaComponent(a))
        }
    }

    func drawBangBubble() {
        let r = NSRect(x: bounds.midX + 6, y: base + 78, width: 26, height: 26)
        bubble(r)
        let s = 20 + sin(phase * 5) * 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s, weight: .heavy), .foregroundColor: warn]
        let str = NSString(string: "!")
        let sz = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: attrs)
    }

    func drawSparkles() {
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

    func drawPill(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold), .foregroundColor: NSColor.white]
        let str = NSString(string: text)
        let sz = str.size(withAttributes: attrs)
        let r = NSRect(x: bounds.midX - sz.width / 2 - 7, y: 4, width: sz.width + 14, height: sz.height + 5)
        ink.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        str.draw(at: CGPoint(x: r.minX + 7, y: r.minY + 2.5), withAttributes: attrs)
    }

    func drawZs() {
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
