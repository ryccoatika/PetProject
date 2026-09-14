//  AppDelegate+Sessions.swift
//  Desktop Pet
//
//  Everything that treats the agent sessions as a group: which one the pose
//  follows, the menu bar badge, and the chime toggle.

import Cocoa

extension AppDelegate {

    /// The session the pose should reflect: the pinned one if it is still
    /// live, otherwise the most urgent. Nil falls back to the state file, so
    /// external producers and single-agent use are unchanged.
    func drivingSession(_ sessions: [AgentSession]) -> AgentSession? {
        if !pinnedSession.isEmpty, let pinned = sessions.first(where: { $0.id == pinnedSession }) {
            return pinned
        }
        // waiting beats a failure beats work beats thinking; ties break newest
        func rank(_ s: AgentSession) -> Int {
            switch s.event {
            case "Notification", "PermissionRequest": return 4
            case "PostToolUseFailure", "StopFailure": return 3
            case "PreToolUse": return 2
            case "UserPromptSubmit", "PostToolUse": return 1
            default: return 0
            }
        }
        return sessions.max { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.stamp < b.stamp
        }
    }

    /// Refresh the menu bar badge from the live sessions: a count, red when
    /// any of them needs you.
    func refreshBadge(_ sessions: [AgentSession]) {
        guard let button = statusItem?.button else { return }
        let waiting = sessions.contains(where: \.isWaiting)
        let count = sessions.count
        let badge = count == 0 ? "" : " \(count)\(waiting ? "!" : "")"
        guard badge != lastBadge else { return }
        lastBadge = badge

        // rebuild the base icon, then append the badge as coloured text
        applyTrayIcon()
        guard !badge.isEmpty else { return }
        let color = waiting ? NSColor.systemRed : NSColor.secondaryLabelColor
        button.attributedTitle = NSAttributedString(
            string: badge,
            attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
    }

    /// Let the chosen session stand in for the state file, so the pose
    /// reflects the session the user is following (or the most urgent one)
    /// rather than whichever agent happened to write last. With no live
    /// session this does nothing and the state file drives, as before.
    func driveFromSession() {
        guard let driver = drivingSession(liveSessions) else { return }
        updateStreak(event: driver.event, stamp: driver.stamp)
        if driver.stamp != lastStamp {
            if event == "" || driver.stamp > lastStamp { idleSince = Date() }
        }
        event = driver.event
        tool = driver.tool
        if !driver.tool.isEmpty { lastTool = driver.tool }
        lastStamp = driver.stamp
        eventAge = driver.age
    }

    /// Count consecutive tool successes and failures off the event stream, so
    /// updatePose can reward a clean run and dwell on a bad patch.
    func updateStreak(event: String, stamp: TimeInterval) {
        guard stamp != lastStreakStamp else { return }
        lastStreakStamp = stamp
        switch event {
        case "PostToolUse":
            successStreak += 1
            failureStreak = 0
        case "PostToolUseFailure", "StopFailure":
            failureStreak += 1
            successStreak = 0
        case "SessionEnd", "SessionStart":
            successStreak = 0
            failureStreak = 0
        default:
            break
        }
    }

    @objc func toggleChime() {
        chimeEnabled.toggle()
        Prefs.store.set(chimeEnabled, forKey: "petChime")
        refreshMenu()
        flash(chimeEnabled ? "chime on" : "chime off")
        if chimeEnabled { NSSound(named: chimeSoundName)?.play() }  // a preview
    }

    /// The Follow Session submenu: auto, then one row per live session.
    func populateFollowMenu() {
        followMenu.removeAllItems()
        let auto = NSMenuItem(
            title: "Most urgent (automatic)", action: #selector(setFollowSession(_:)),
            keyEquivalent: "")
        auto.target = self
        auto.representedObject = ""
        auto.state = pinnedSession.isEmpty ? .on : .off
        followMenu.addItem(auto)

        let sessions = SessionStore.read()
        if !sessions.isEmpty {
            followMenu.addItem(.separator())
            for session in sessions {
                let label = session.project.isEmpty ? "Agent" : session.project
                let detail = session.activity.map { " — \($0)" } ?? ""
                let it = NSMenuItem(
                    title: "\(label)\(detail)", action: #selector(setFollowSession(_:)),
                    keyEquivalent: "")
                it.target = self
                it.representedObject = session.id
                it.state = session.id == pinnedSession ? .on : .off
                followMenu.addItem(it)
            }
        }
        // a stale pin still gets its own row so it can be cleared
        if !pinnedSession.isEmpty, !sessions.contains(where: { $0.id == pinnedSession }) {
            followMenu.addItem(.separator())
            let it = NSMenuItem(
                title: "Pinned session (ended)", action: #selector(setFollowSession(_:)),
                keyEquivalent: "")
            it.target = self
            it.representedObject = pinnedSession
            it.state = .on
            followMenu.addItem(it)
        }
    }

    @objc func setFollowSession(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        pinnedSession = id
        if id.isEmpty {
            Prefs.store.removeObject(forKey: "petFollowSession")
            flash("following most urgent")
        } else {
            Prefs.store.set(id, forKey: "petFollowSession")
        }
        populateFollowMenu()
    }
}
