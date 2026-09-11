//  PetView.swift
//  Desktop Pet
//
//  The pet's view: state, dragging, and the drawing entry points.

import Cocoa

final class PetView: NSView {
    var pose: Pose = .sitting
    var facingRight = true
    var phase: CGFloat = 0
    var blink: CGFloat = 0
    var eyeOffset = CGPoint.zero
    var zPhase: CGFloat = 0
    var label: String? = nil          // pill text under the pet
    /// A brief confirmation of something the user just did. Shown for every
    /// skin, where `label` describes the activity and sprite packs do not.
    var flashLabel: String? = nil
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
        sprite == nil ? NSRect(x: bounds.midX - 45, y: 0, width: 90, height: 118)
                      : NSRect(x: bounds.midX - 62, y: 0, width: 124, height: bounds.height - 24)
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
    /// When set, the pet is drawn from a spritesheet instead of vector art.
    var sprite: SpritePet?
    var spriteFrame = 0
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

    func fillStroke(_ p: NSBezierPath, _ color: NSColor, _ lw: CGFloat = 1.6) {
        color.setFill(); p.fill()
        ink.setStroke(); p.lineWidth = lw; p.lineJoinStyle = .round; p.lineCapStyle = .round; p.stroke()
    }
    func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat,
                      _ color: NSColor, _ lw: CGFloat = 1.6) {
        fillStroke(NSBezierPath(ovalIn: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h)), color, lw)
    }
    func plainOval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h)).fill()
    }
    /// Paw / limb colour: pandas wear their dark tone on the extremities.
    var paw: NSColor { skin.darkLimbs ? furDk : cream }
    var limbColor: NSColor { skin.darkLimbs ? furDk : fur }

    func limb(_ from: CGPoint, _ to: CGPoint, _ w: CGFloat = 5) {
        let p = NSBezierPath(); p.move(to: from); p.line(to: to)
        p.lineWidth = w + 2.6; p.lineCapStyle = .round; ink.setStroke(); p.stroke()
        p.lineWidth = w; limbColor.setStroke(); p.stroke()
    }
    func tail(from: CGPoint, to: CGPoint, c1: CGPoint, c2: CGPoint) {
        let t = NSBezierPath()
        t.move(to: from); t.curve(to: to, controlPoint1: c1, controlPoint2: c2)
        t.lineWidth = 8.6; t.lineCapStyle = .round; ink.setStroke(); t.stroke()
        t.lineWidth = 6; limbColor.setStroke(); t.stroke()
    }

    // MARK: draw

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high

        if let sprite {
            drawSprite(sprite)
            return
        }

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
        case .alert, .failed: drawAlertPose()
        case .celebrate: drawCelebrate()
        case .working:   drawWorking()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Bubbles and labels are never mirrored, so they live outside the flip.
        switch pose {
        case .sleeping:      drawZs()
        case .thinking:      drawThoughtBubble()
        case .alert, .failed: drawBangBubble()
        case .celebrate:     drawSparkles()
        default: break
        }
        if let l = flashLabel ?? label { drawPill(l) }
    }

    /// Spritesheet pets use the atlas rows in place of the drawn poses.
    ///
    /// No pill and no bubbles: the pack animates what it is doing — Running
    /// while a tool runs, Review while thinking, Waiting when it needs you —
    /// so the drawn ornaments would only cover the art. A confirmation the
    /// user just asked for ("chase on", "installing…") is still worth showing.
    func drawSprite(_ sprite: SpritePet) {
        let box = NSRect(x: 0, y: 16, width: bounds.width, height: bounds.height - 26)
        sprite.draw(track: spriteTrack, frame: spriteFrame, in: box)
        if let flashLabel { drawPill(flashLabel) }
    }

    /// Which atlas row the current pose maps to.
    ///
    ///   Idle          sitting, and sleeping (slowed down)
    ///   Run right/left  walking, by direction
    ///   Waving        being picked up
    ///   Jumping       a turn just finished
    ///   Failed        the agent reported a failure
    ///   Waiting       waiting for you (permission / notification)
    ///   Running       a tool is running
    ///   Review        thinking between steps
    ///   Look around   idle glancing, toward whichever side the cursor is on
    var spriteTrack: SpritePet.Track {
        if held { return .waving }
        switch pose {
        case .running:   return facingRight ? .runningRight : .runningLeft
        case .working:   return .running
        case .thinking:  return .review
        case .alert:     return .waiting
        case .celebrate: return .jumping
        case .grooming:  return facingRight ? .lookAroundRight : .lookAroundLeft
        case .failed:    return .failed
        default:         return .idle
        }
    }
}
