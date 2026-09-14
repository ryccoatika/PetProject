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
    /// What the agent is actually doing — the prompt it was given or the
    /// tool call's own words — when the payload offered one.
    let detail: String
    /// The session's working directory, for click-to-open. May be empty.
    let cwd: String

    var age: TimeInterval { Date().timeIntervalSince1970 - stamp }

    /// True while the session needs the user — a permission or notification.
    var isWaiting: Bool {
        (event == "Notification" || event == "PermissionRequest") && age < 1800
    }

    /// What the card should say, or nil when this session has gone quiet.
    /// Needing attention lingers; starting and finishing fade in 5 seconds.
    var activity: String? {
        switch event {
        case "PostToolUseFailure", "StopFailure":
            return age < 300 ? "A tool failed" : nil
        case "Notification", "PermissionRequest":
            return age < 1800 ? "Waiting for you" : nil
        case "PreToolUse":
            if age >= 600 { return nil }
            if !detail.isEmpty { return detail }
            return "Running \(tool.isEmpty ? "a tool" : tool)"
        case "UserPromptSubmit", "PostToolUse":
            if age >= 600 { return nil }
            return detail.isEmpty ? "Thinking" : detail
        case "SessionStart":
            return age < 5 ? "Starting" : nil
        case "Stop":
            return age < 5 ? "Finished" : nil
        default:
            return nil
        }
    }

    var title: String { project.isEmpty ? "Agent" : project }
}

enum SessionStore {
    static var dir: URL { SkinStore.configDir.appendingPathComponent("sessions") }

    /// Every live session, newest first. Files from sessions that died long
    /// ago are cleaned up on the way through.
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
            let cwd =
                parts.count > 5
                ? (Data(base64Encoded: parts[5]).flatMap { String(data: $0, encoding: .utf8) } ?? "")
                : ""
            let session = AgentSession(
                id: name, event: parts[0], tool: parts[1], stamp: ts,
                project: parts.count > 3 ? parts[3] : "",
                detail: parts.count > 4 ? parts[4] : "", cwd: cwd)
            if session.age > 86_400 {
                try? FileManager.default.removeItem(at: file)  // ended without a SessionEnd
                continue
            }
            sessions.append(session)
        }
        return sessions.sorted { $0.stamp > $1.stamp }
    }

    /// Only the sessions with something worth showing on a card.
    static func active() -> [AgentSession] { read().filter { $0.activity != nil } }
}

/// Draws the stack of cards. Index 0 — the newest — sits at the bottom,
/// nearest the pet.
final class BubbleView: NSView {
    var sessions: [AgentSession] = [] { didSet { needsDisplay = true } }
    /// Called with a session's working directory when its card is clicked.
    var onClick: ((AgentSession) -> Void)?

    static let cardHeight: CGFloat = 44
    static let spacing: CGFloat = 6
    static let titleFont = NSFont.boldSystemFont(ofSize: 12)
    static let subtitleFont = NSFont.systemFont(ofSize: 11)

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let slot = Self.cardHeight + Self.spacing
        let i = Int(p.y / slot)
        guard i >= 0, i < sessions.count else { return }
        // ignore a click that lands in the gap between two cards
        if p.y - CGFloat(i) * slot > Self.cardHeight { return }
        onClick?(sessions[i])
    }

    // a card only wants the click when it can act on it
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let slot = Self.cardHeight + Self.spacing
        let i = Int(local.y / slot)
        guard i >= 0, i < sessions.count, !sessions[i].cwd.isEmpty else { return nil }
        if local.y - CGFloat(i) * slot > Self.cardHeight { return nil }
        return self
    }

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
        chimeIfNewlyWaiting(liveSessions)
        refreshBadge(liveSessions)
        guard bubblesEnabled, !hidden else {
            hideBubbles()
            return
        }
        let sessions = Array(liveSessions.filter { $0.activity != nil }.prefix(4))
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
        // clicks land on a card and pass through everywhere else (hitTest)
        window.ignoresMouseEvents = false
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        window.contentView = view
        view.onClick = { [weak self] session in self?.openSession(session) }
        bubbleView = view
        bubbleWindow = window
        return window
    }

    /// Open a clicked session's project folder in Finder.
    func openSession(_ session: AgentSession) {
        guard !session.cwd.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
    }

    /// Chime once when a session first starts waiting for the user. Only
    /// sessions we have already seen count, so a chime does not fire for
    /// everything already waiting when the pet launches.
    func chimeIfNewlyWaiting(_ sessions: [AgentSession]) {
        let waiting = Set(sessions.filter(\.isWaiting).map(\.id))
        defer { lastWaitingSessions = waiting }
        guard chimeEnabled, bubbleWindowSeenOnce else {
            bubbleWindowSeenOnce = true
            return
        }
        if !waiting.subtracting(lastWaitingSessions).isEmpty {
            NSSound(named: chimeSoundName)?.play()
        }
    }

    @objc func toggleBubbles() {
        bubblesEnabled.toggle()
        Prefs.store.set(!bubblesEnabled, forKey: "petBubblesHidden")
        if !bubblesEnabled { hideBubbles() }
        refreshMenu()
        flash(bubblesEnabled ? "bubbles on" : "bubbles off")
    }
}
