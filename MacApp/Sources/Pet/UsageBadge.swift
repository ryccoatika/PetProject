//  UsageBadge.swift
//  Desktop Pet
//
//  A small card below the pet with Claude's own rate-limit numbers — the
//  same two bars /usage shows. Persistent while data is fresh, unlike the
//  activity bubbles above the pet, which come and go with what is happening.

import Cocoa

final class UsageBadgeView: NSView {
    var snapshot: UsageStore.Snapshot? { didSet { needsDisplay = true } }

    static let width: CGFloat = 210
    static let height: CGFloat = 38
    static let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    static let trailingFont = NSFont.systemFont(ofSize: 10, weight: .regular)

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        card.fill()
        NSColor.separatorColor.setStroke()
        card.lineWidth = 0.5
        card.stroke()

        guard let snapshot else { return }
        row(
            label: "Session", pct: snapshot.sessionPercent,
            reset: UsageStore.humanReset(snapshot.sessionResetsAt), y: 20)
        row(
            label: "Week", pct: snapshot.weekPercent,
            reset: UsageStore.humanReset(snapshot.weekResetsAt), y: 4)
    }

    /// One self-contained line: label, a short bar, then the percentage and
    /// reset countdown — everything at one baseline, so two rows can never
    /// collide regardless of font metrics.
    private func row(label: String, pct: Double?, reset: String?, y: CGFloat) {
        guard let pct else { return }
        let barX: CGFloat = 58, barW: CGFloat = 74, barH: CGFloat = 6
        let barY = y + 3

        (label as NSString).draw(
            at: CGPoint(x: 10, y: y),
            withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])

        let track = NSBezierPath(
            roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH), xRadius: 3,
            yRadius: 3)
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        track.fill()
        let filled = max(0, min(1, pct / 100)) * barW
        if filled > 1 {
            let fill = NSBezierPath(
                roundedRect: NSRect(x: barX, y: barY, width: filled, height: barH), xRadius: 3,
                yRadius: 3)
            barColor(for: pct).setFill()
            fill.fill()
        }

        let trailing = "\(Int(pct))%" + (reset.map { " · \($0)" } ?? "")
        (trailing as NSString).draw(
            at: CGPoint(x: barX + barW + 8, y: y),
            withAttributes: [
                .font: Self.trailingFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])
    }

    /// Green well under budget, amber approaching the limit, red at it.
    private func barColor(for pct: Double) -> NSColor {
        pct >= 95
            ? NSColor.systemRed
            : pct >= 75 ? NSColor.systemOrange : NSColor.systemGreen
    }
}

extension AppDelegate {

    /// Re-read the usage file and show or hide the badge below the pet.
    /// Called on the same slow tick as the activity bubbles.
    func updateUsageBadge() {
        guard usageEnabled, !hidden else {
            hideUsageBadge()
            return
        }
        guard let snapshot = UsageStore.read(), snapshot.age < UsageStore.staleAfter else {
            hideUsageBadge()
            return
        }
        let window = usageWindow ?? makeUsageWindow()
        usageView?.snapshot = snapshot
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
            frame: NSRect(x: 0, y: 0, width: UsageBadgeView.width, height: UsageBadgeView.height))
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
