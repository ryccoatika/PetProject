//  ActivityBubbles.swift
//  Desktop Pet
//
//  The message bubbles above the pet's head: one card per active agent
//  session, so several projects running at once stack up.

import Cocoa

/// One agent session, read back from its file in <configDir>/sessions/.
struct AgentSession {
    let id: String
    let event: String
    let tool: String
    let stamp: TimeInterval
    let project: String

    var age: TimeInterval { Date().timeIntervalSince1970 - stamp }

    /// What the card should say, or nil when this session has gone quiet.
    /// Needing attention lingers; finishing fades quickly.
    var activity: String? {
        switch event {
        case "PostToolUseFailure", "StopFailure":
            return age < 300 ? "A tool failed" : nil
        case "Notification", "PermissionRequest":
            return age < 1800 ? "Waiting for you" : nil
        case "PreToolUse":
            return age < 600 ? "Running \(tool.isEmpty ? "a tool" : tool)" : nil
        case "UserPromptSubmit", "PostToolUse":
            return age < 600 ? "Thinking" : nil
        case "SessionStart":
            return age < 60 ? "Starting" : nil
        case "Stop":
            return age < 60 ? "Finished" : nil
        default:
            return nil
        }
    }

    var title: String { project.isEmpty ? "Agent" : project }
}

enum SessionStore {
    static var dir: URL { SkinStore.configDir.appendingPathComponent("sessions") }

    /// Sessions with something to show, newest first. Files from sessions
    /// that died long ago are cleaned up on the way through.
    static func read() -> [AgentSession] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        var sessions: [AgentSession] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let file = dir.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "|")
            guard parts.count >= 3, let ts = TimeInterval(parts[2]) else { continue }
            let session = AgentSession(
                id: name, event: parts[0], tool: parts[1], stamp: ts,
                project: parts.count > 3 ? parts[3] : "")
            if session.age > 86_400 {
                try? FileManager.default.removeItem(at: file)  // ended without a SessionEnd
                continue
            }
            sessions.append(session)
        }
        return sessions.filter { $0.activity != nil }.sorted { $0.stamp > $1.stamp }
    }
}

/// Draws the stack of cards. Index 0 — the newest — sits at the bottom,
/// nearest the pet.
final class BubbleView: NSView {
    var sessions: [AgentSession] = [] { didSet { needsDisplay = true } }

    static let cardHeight: CGFloat = 44
    static let spacing: CGFloat = 6
    static let titleFont = NSFont.boldSystemFont(ofSize: 12)
    static let subtitleFont = NSFont.systemFont(ofSize: 11)

    static func stackHeight(for count: Int) -> CGFloat {
        count == 0 ? 0 : CGFloat(count) * cardHeight + CGFloat(count - 1) * spacing
    }

    /// Wide enough for the longest line, within reason.
    static func stackWidth(for sessions: [AgentSession]) -> CGFloat {
        var width: CGFloat = 0
        for session in sessions {
            let title = (session.title as NSString).size(withAttributes: [.font: titleFont])
            let sub = ((session.activity ?? "") as NSString)
                .size(withAttributes: [.font: subtitleFont])
            width = max(width, max(title.width, sub.width))
        }
        return min(max(width + 32, 150), 280)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, session) in sessions.enumerated() {
            let y = CGFloat(i) * (Self.cardHeight + Self.spacing)
            drawCard(session, in: NSRect(x: 0, y: y, width: bounds.width, height: Self.cardHeight))
        }
    }

    private func drawCard(_ session: AgentSession, in rect: NSRect) {
        let card = NSBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        card.fill()
        NSColor.separatorColor.setStroke()
        card.lineWidth = 0.5
        card.stroke()

        let truncate = NSMutableParagraphStyle()
        truncate.lineBreakMode = .byTruncatingTail
        let text = NSRect(x: rect.minX + 15, y: rect.minY, width: rect.width - 30, height: 0)

        (session.title as NSString).draw(
            in: NSRect(x: text.minX, y: rect.minY + 23, width: text.width, height: 16),
            withAttributes: [
                .font: Self.titleFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: truncate,
            ])
        ((session.activity ?? "") as NSString).draw(
            in: NSRect(x: text.minX, y: rect.minY + 7, width: text.width, height: 15),
            withAttributes: [
                .font: Self.subtitleFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: truncate,
            ])
    }
}

extension AppDelegate {

    /// Re-read the sessions and lay the stack out. Called on a slow tick;
    /// cheap when nothing changed.
    func updateBubbles() {
        guard bubblesEnabled, !hidden else {
            hideBubbles()
            return
        }
        let sessions = Array(SessionStore.read().prefix(4))
        guard !sessions.isEmpty else {
            hideBubbles()
            return
        }

        let signature = sessions.map { "\($0.id)|\($0.event)|\($0.tool)|\($0.stamp)" }
            .joined(separator: ",")
        let window = bubbleWindow ?? makeBubbleWindow()
        if signature != bubbleSignature {
            bubbleSignature = signature
            bubbleView?.sessions = sessions
            window.setContentSize(
                NSSize(
                    width: BubbleView.stackWidth(for: sessions),
                    height: BubbleView.stackHeight(for: sessions.count)))
        }
        placeBubbles()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hideBubbles() {
        guard let window = bubbleWindow, window.isVisible else { return }
        window.orderOut(nil)
        bubbleSignature = ""
    }

    /// Centred above the pet, kept on the screen.
    func placeBubbles() {
        guard let bubble = bubbleWindow else { return }
        let width = bubble.frame.width
        let screen =
            NSScreen.screens.first { $0.frame.contains(pos) } ?? NSScreen.main
            ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let x = min(max(pos.x - width / 2, f.minX + 4), f.maxX - width - 4)
        let y = min(window.frame.maxY - 20 * artScale, f.maxY - bubble.frame.height - 4)
        let origin = NSPoint(x: x.rounded(), y: y.rounded())
        if abs(bubble.frame.minX - origin.x) > 0.5 || abs(bubble.frame.minY - origin.y) > 0.5 {
            bubble.setFrameOrigin(origin)
        }
    }

    private func makeBubbleWindow() -> NSWindow {
        let view = BubbleView(frame: .zero)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 150, height: BubbleView.cardHeight),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        window.contentView = view
        bubbleView = view
        bubbleWindow = window
        return window
    }

    @objc func toggleBubbles() {
        bubblesEnabled.toggle()
        Prefs.store.set(!bubblesEnabled, forKey: "petBubblesHidden")
        if !bubblesEnabled { hideBubbles() }
        refreshMenu()
        flash(bubblesEnabled ? "bubbles on" : "bubbles off")
    }
}
