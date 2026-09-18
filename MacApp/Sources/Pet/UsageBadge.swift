//  UsageBadge.swift
//  Desktop Pet
//
//  A small card below the pet with Claude's own rate-limit numbers — the
//  same two figures /usage shows, per account. Circular rather than a bar
//  per account so several accounts (~/.claude, ~/.claude-account1, …) fit
//  side by side without the card growing tall. No caption under each ring
//  by default — hovering one shows its account name in a small pill above
//  the card, so the badge stays as compact as the numbers alone need.
//
//  The label is drawn by the view itself rather than a native NSView
//  tooltip: this window is a borderless, non-activating overlay owned by an
//  accessory app, and native tooltip tracking proved unreliable there. The
//  main loop already polls NSEvent.mouseLocation every tick for the pet's
//  own hover and drag handling, so hover here rides the same poll instead
//  of depending on AppKit's own mouse-tracking machinery.

import Cocoa

final class UsageBadgeView: NSView {
    var snapshots: [UsageStore.Snapshot] = [] { didSet { needsDisplay = true } }
    /// Which account the cursor is over, set every tick by the main loop.
    var hoveredIndex: Int? {
        didSet { if oldValue != hoveredIndex { needsDisplay = true } }
    }

    static let diameter: CGFloat = 40
    static let ringWidth: CGFloat = 4
    static let ringGap: CGFloat = 2
    static let spacing: CGFloat = 14
    static let sidePadding: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    /// Room above the card for the hover pill — invisible the rest of the
    /// time, so the resting badge looks exactly as compact as the rings.
    static let hoverStripHeight: CGFloat = 20
    static let cardHeight: CGFloat = diameter + verticalPadding * 2
    static let height: CGFloat = cardHeight + hoverStripHeight
    /// Never lets the card grow absurdly wide; more accounts than this are
    /// simply not shown (`pet usage` on the command line has no such limit).
    static let maxAccounts = 6

    static func width(for count: Int) -> CGFloat {
        let n = CGFloat(min(count, maxAccounts))
        return n * diameter + max(0, n - 1) * spacing + sidePadding * 2
    }

    static let centerFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let hoverFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    /// The x-centre of the i-th ring, in this view's own coordinates —
    /// shared by drawing and by the hover hit-test so they can never drift
    /// apart.
    static func centerX(for index: Int) -> CGFloat {
        sidePadding + diameter / 2 + CGFloat(index) * (diameter + spacing)
    }

    /// Which account, if any, a point in this view's own coordinates sits
    /// over. Used by the main loop, not by AppKit's own hit-testing.
    func slotIndex(at point: NSPoint) -> Int? {
        guard point.y >= Self.hoverStripHeight, point.y <= Self.height else { return nil }
        for i in 0..<min(snapshots.count, Self.maxAccounts) {
            let x = Self.centerX(for: i)
            if abs(point.x - x) <= Self.diameter / 2 { return i }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let cardRect = NSRect(
            x: 1, y: 1, width: bounds.width - 2, height: Self.cardHeight - 2)
        let card = NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        card.fill()
        NSColor.separatorColor.setStroke()
        card.lineWidth = 0.5
        card.stroke()

        let cy = Self.cardHeight / 2
        for (i, snap) in snapshots.prefix(Self.maxAccounts).enumerated() {
            drawAccount(snap, center: NSPoint(x: Self.centerX(for: i), y: cy))
        }

        if let i = hoveredIndex, i < snapshots.count {
            drawHoverPill(label: snapshots[i].label, above: Self.centerX(for: i))
        }
    }

    private func drawAccount(_ snap: UsageStore.Snapshot, center: NSPoint) {
        let outerR = (Self.diameter - Self.ringWidth) / 2
        let innerR = outerR - Self.ringWidth - Self.ringGap

        ring(pct: snap.weekPercent, center: center, radius: outerR)
        ring(pct: snap.sessionPercent, center: center, radius: innerR)

        if let worst = snap.worstPercent {
            let text = "\(Int(worst))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.centerFont, .foregroundColor: barColor(for: worst),
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                withAttributes: attrs)
        }
    }

    /// A small dark pill floating above the card, in the reserved strip —
    /// never clipped, since that strip is real view height, just usually
    /// empty.
    private func drawHoverPill(label: String, above cx: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.hoverFont, .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 7
        let pillWidth = size.width + padding * 2
        let pillHeight: CGFloat = 16
        var x = cx - pillWidth / 2
        x = max(2, min(x, bounds.width - pillWidth - 2))
        let rect = NSRect(
            x: x, y: Self.height - pillHeight - 2, width: pillWidth, height: pillHeight)
        // a fixed dark fill, not a dynamic system colour: labelColor flips
        // to near-white in dark mode and all but disappears against this
        // transparent backdrop.
        NSColor(white: 0.12, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
        (label as NSString).draw(
            at: CGPoint(
                x: rect.midX - size.width / 2, y: rect.minY + (pillHeight - size.height) / 2),
            withAttributes: attrs)
    }

    /// One ring: a full track, then a progress arc clockwise from 12
    /// o'clock. `nil` draws nothing — an account with only one window
    /// reporting still gets its one ring centred correctly.
    private func ring(pct: Double?, center: NSPoint, radius: CGFloat) {
        guard let pct else { return }
        let track = NSBezierPath()
        track.appendArc(
            withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        track.lineWidth = Self.ringWidth
        track.stroke()

        let fraction = max(0, min(1, pct / 100))
        guard fraction > 0.003 else { return }
        let progress = NSBezierPath()
        let start: CGFloat = 90
        let end = start - 360 * CGFloat(fraction)
        progress.appendArc(
            withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        barColor(for: pct).setStroke()
        progress.lineWidth = Self.ringWidth
        progress.lineCapStyle = .round
        progress.stroke()
    }

    /// Green well under budget, amber approaching the limit, red at it.
    private func barColor(for pct: Double) -> NSColor {
        pct >= 95
            ? NSColor.systemRed
            : pct >= 75 ? NSColor.systemOrange : NSColor.systemGreen
    }
}

extension AppDelegate {

    /// Re-read every account's usage file and show or hide the badge below
    /// the pet. Called on the same slow tick as the activity bubbles.
    func updateUsageBadge() {
        guard usageEnabled, !hidden else {
            hideUsageBadge()
            return
        }
        let fresh = UsageStore.readAll().filter { $0.age < UsageStore.staleAfter }
        guard !fresh.isEmpty else {
            hideUsageBadge()
            return
        }
        let width = UsageBadgeView.width(for: fresh.count)
        let window = usageWindow ?? makeUsageWindow()
        if window.frame.width != width {
            window.setContentSize(NSSize(width: width, height: UsageBadgeView.height))
        }
        usageView?.snapshots = fresh
        placeUsageBadge()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hideUsageBadge() {
        guard let window = usageWindow, window.isVisible else { return }
        window.orderOut(nil)
        usageView?.hoveredIndex = nil  // stale otherwise the next time it shows
    }

    /// Called every animation tick alongside the pet's own hover test, so
    /// the label appears the moment the cursor reaches a ring rather than
    /// waiting for the half-second usage-file poll.
    func updateUsageHover(screenPoint: NSPoint) {
        guard let window = usageWindow, window.isVisible, let view = usageView else { return }
        let local = NSPoint(
            x: screenPoint.x - window.frame.minX, y: screenPoint.y - window.frame.minY)
        view.hoveredIndex = view.bounds.contains(local) ? view.slotIndex(at: local) : nil
    }

    /// Centred below the pet, kept on the screen.
    func placeUsageBadge() {
        guard let badge = usageWindow else { return }
        let width = badge.frame.width
        let screen =
            NSScreen.screens.first { $0.frame.contains(pos) } ?? NSScreen.main
            ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let x = min(max(pos.x - width / 2, f.minX + 4), f.maxX - width - 4)
        let y = max(window.frame.minY - badge.frame.height - 6, f.minY + 4)
        let origin = NSPoint(x: x.rounded(), y: y.rounded())
        if abs(badge.frame.minX - origin.x) > 0.5 || abs(badge.frame.minY - origin.y) > 0.5 {
            badge.setFrameOrigin(origin)
        }
    }

    private func makeUsageWindow() -> NSWindow {
        let view = UsageBadgeView(
            frame: NSRect(
                x: 0, y: 0, width: UsageBadgeView.width(for: 1), height: UsageBadgeView.height))
        let window = NSWindow(
            contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        // a readout, nothing to click — hover is tracked separately from
        // NSEvent.mouseLocation on the main loop, so this stays click-through
        window.ignoresMouseEvents = true
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        window.contentView = view
        usageView = view
        usageWindow = window
        return window
    }

    @objc func toggleUsageBadge() {
        usageEnabled.toggle()
        Prefs.store.set(!usageEnabled, forKey: "petUsageHidden")
        if !usageEnabled { hideUsageBadge() }
        refreshMenu()
        flash(usageEnabled ? "usage badge on" : "usage badge off")
    }
}
