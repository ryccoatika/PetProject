//  UsageBadge.swift
//  Desktop Pet
//
//  A small card below the pet with Claude's own rate-limit numbers — the
//  same two figures /usage shows, per account. Circular rather than a bar
//  per account so several accounts (~/.claude, ~/.claude-account1, …) fit
//  side by side without the card growing tall. Persistent while data is
//  fresh, unlike the activity bubbles above the pet, which come and go with
//  what is happening.

import Cocoa

final class UsageBadgeView: NSView {
    var snapshots: [UsageStore.Snapshot] = [] { didSet { needsDisplay = true } }

    static let diameter: CGFloat = 40
    static let ringWidth: CGFloat = 4
    static let ringGap: CGFloat = 2
    static let spacing: CGFloat = 14
    static let sidePadding: CGFloat = 10
    static let labelHeight: CGFloat = 13
    static let height: CGFloat = diameter + labelHeight + 10
    /// Never lets the card grow absurdly wide; more accounts than this are
    /// simply not shown (`pet usage` on the command line has no such limit).
    static let maxAccounts = 6

    static func width(for count: Int) -> CGFloat {
        let n = CGFloat(min(count, maxAccounts))
        return n * diameter + max(0, n - 1) * spacing + sidePadding * 2
    }

    static let centerFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    static let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .regular)

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        card.fill()
        NSColor.separatorColor.setStroke()
        card.lineWidth = 0.5
        card.stroke()

        let d = Self.diameter
        let cy = Self.labelHeight + 5 + d / 2
        for (i, snap) in snapshots.prefix(Self.maxAccounts).enumerated() {
            let cx = Self.sidePadding + d / 2 + CGFloat(i) * (d + Self.spacing)
            drawAccount(snap, center: NSPoint(x: cx, y: cy))
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

        let label = snap.label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont, .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let maxWidth = Self.diameter + Self.spacing - 4
        let truncated =
            labelSize.width > maxWidth
            ? String(label.prefix(6)) + "…" : label
        let finalSize = (truncated as NSString).size(withAttributes: labelAttrs)
        (truncated as NSString).draw(
            at: CGPoint(x: center.x - finalSize.width / 2, y: 2), withAttributes: labelAttrs)
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
        window.ignoresMouseEvents = true  // a readout, nothing to click
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
