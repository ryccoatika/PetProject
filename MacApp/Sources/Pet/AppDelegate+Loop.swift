//  AppDelegate+Loop.swift
//  Desktop Pet
//
//  The animation loop: its rate, placement, reading activity, and each step.

import Cocoa

extension AppDelegate {

    /// these wakeups with others instead of waking the CPU on its own.
    func setLoopRate(_ rate: Double) {
        guard rate != currentFPS else { return }
        currentFPS = rate
        timer?.invalidate()
        let t = Timer(timeInterval: 1 / rate, repeats: true) { [weak self] _ in self?.step() }
        t.tolerance = (1 / rate) * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 30fps while moving or reacting, 10 while idling, 2 while hidden.
    func desiredLoopRate() -> Double {
        if hidden { return 2 }
        // Motion is what the eye catches, so only movement gets the full rate.
        if dragging || view.held || view.pose == .running { return 30 }
        if isActive { return 20 }  // typing, thinking, alerting
        // chasing: wake up while the cursor is actually moving, so the pet
        // starts after it without a visible delay
        if chaseWhenIdle, Date().timeIntervalSince(lastMouseMove) < 0.6 { return 30 }
        if view.pose == .sleeping { return 3 }
        return 6
    }

    func writeRuntime() {
        let dir = SkinStore.configDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line =
            "pid=\(ProcessInfo.processInfo.processIdentifier) "
            + "skin=\(view.sprite?.id ?? view.skin.id) "
            + "hidden=\(hidden ? 1 : 0) chase=\(chaseWhenIdle ? 1 : 0) "
            + "tray=\(trayHidden ? "hidden" : "shown") "
            + "cli=\(cliReachable ? "ok" : "needs-path") "
            + "size=\(Int(artScale * 100))%\n"
        try? line.write(
            to: dir.appendingPathComponent("runtime"), atomically: true, encoding: .utf8)
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
        // a missing key means the default size, which is how `pet size reset`
        // clears it — reading it as "no change" would ignore the reset
        let savedScale = CGFloat((d.object(forKey: "petScale") as? Double) ?? 1)
        if savedScale != artScale { setArtScale(savedScale, save: false) }
        let wantTrayHidden = d.bool(forKey: "petTrayHidden")
        if wantTrayHidden != trayHidden {
            trayHidden = wantTrayHidden
            if trayHidden { removeTray() } else { showTray() }
        }
        reloadSkins()
        if let id = d.string(forKey: "petSkin") { _ = applyArt(id: id) }
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
        let screen =
            NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        return CGPoint(
            x: min(max(p.x, f.minX + 50), f.maxX - 50),
            y: min(max(p.y, f.minY + 4), f.maxY - size.height))
    }

    /// Moving a window is a trip to the window server; skip it when the pet
    /// has not actually moved.
    /// Resize the window to suit the current art, keeping the pet in place.
    func applyWindowSize() {
        let design = view.sprite == nil ? AppDelegate.vectorSize : AppDelegate.spriteSize
        let wanted = NSSize(
            width: (design.width * artScale).rounded(),
            height: (design.height * artScale).rounded())
        guard wanted != size || view.bounds.size != design else { return }
        size = wanted
        window.setContentSize(wanted)
        view.frame = NSRect(origin: .zero, size: wanted)
        // Drawing stays in design coordinates: AppKit scales a view whose
        // bounds are smaller than its frame, so no art has to know about this.
        view.setBoundsSize(design)
        placedAt = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)  // force a reposition
        pos = clampToScreen(pos)
        place()
        view.needsDisplay = true
    }

    /// Change how big the pet is drawn. Clamped, saved, and applied at once.
    func setArtScale(_ value: CGFloat, save: Bool = true) {
        let clamped = min(
            max(value, AppDelegate.scaleRange.lowerBound),
            AppDelegate.scaleRange.upperBound)
        guard clamped != artScale else { return }
        artScale = clamped
        if save {
            Prefs.store.set(Double(clamped), forKey: "petScale")
            Prefs.store.synchronize()
        }
        applyWindowSize()
        writeRuntime()
    }

    func place() {
        guard abs(pos.x - placedAt.x) > 0.5 || abs(pos.y - placedAt.y) > 0.5 else { return }
        placedAt = pos
        window.setFrameOrigin(NSPoint(x: pos.x - size.width / 2, y: pos.y))
    }

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
            if quiet > 25 {
                view.pose = .sleeping; view.zPhase += 0.006 * tickScale
            } else if quiet > 10 && Int(quiet) % 6 < 2 {
                view.pose = .grooming
            } else {
                view.pose = .sitting
            }
        }

        switch event {
        case "PostToolUseFailure" where eventAge < 6, "StopFailure" where eventAge < 6:
            view.pose = .failed; view.label = "failed"
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

    /// Sprite pets animate at a fixed rate regardless of the 30fps redraw.
    func advanceSprite() {
        guard let sprite = view.sprite else { return }
        let track = view.spriteTrack
        let frames = sprite.frames(in: track)
        guard frames > 1 else { view.spriteFrame = 0; return }
        // idle and sleep breathe slowly; movement and reactions run quicker
        let interval =
            view.pose == .sleeping
            ? 0.47
            : (isActive || view.pose == .running ? 0.13 : 0.27)
        sinceSpriteFrame += 1 / max(currentFPS, 1)
        if sinceSpriteFrame >= interval {
            sinceSpriteFrame = 0
            view.spriteFrame = (view.spriteFrame + 1) % frames
        }
        if track != lastTrack {
            lastTrack = track
            view.spriteFrame = 0  // restart a track from its first frame
        }
    }

    // MARK: frame

    func step() {
        tick += 1

        let dt = 1 / max(currentFPS, 1)
        sinceStateRead += dt

        if hidden {  // still follow Claude so the menu stays useful
            if sinceStateRead >= 0.1 { sinceStateRead = 0; readState() } else { eventAge += dt }
            updatePose()
            isActive = [.working, .thinking, .alert, .celebrate, .failed].contains(view.pose)
            setLoopRate(desiredLoopRate())
            return
        }

        let mouseNow = NSEvent.mouseLocation
        if hypot(mouseNow.x - lastMousePoint.x, mouseNow.y - lastMousePoint.y) > 2 {
            lastMousePoint = mouseNow
            lastMouseMove = Date()
        }

        // Per-pixel click-through: the window takes the mouse whenever the
        // cursor is over the cat itself, so it can always be grabbed or
        // double-clicked; everywhere else clicks pass through.
        // Never re-evaluate mid-drag: a fast drag can outrun the window and
        // would otherwise make it click-through, dropping the cat.
        if !dragging {
            let local = NSPoint(
                x: mouseNow.x - window.frame.minX, y: mouseNow.y - window.frame.minY)
            let grabbable = view.grabRect.contains(local)
            if window.ignoresMouseEvents == grabbable { window.ignoresMouseEvents = !grabbable }
        }

        if dragging {  // user is holding it: no autonomy
            view.phase += 0.3
            view.needsDisplay = true
            return
        }

        if sinceStateRead >= 0.1 { sinceStateRead = 0; readState() } else { eventAge += dt }
        updatePose()

        let active = [.working, .thinking, .alert, .celebrate, .failed].contains(view.pose)
        isActive = active
        advanceSprite()
        view.flashLabel = Date() < flashUntil ? flashText : nil
        view.phase += (active ? 0.3 : 0.07) * tickScale
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
            let speed = min(3 + dist * 0.07, 11) * tickScale
            pos = CGPoint(x: pos.x + dx / dist * speed, y: pos.y + dy / dist * speed)
            if !active {
                view.pose = .running
                view.label = nil
                view.phase += 0.32 * tickScale
                if abs(dx) > 2 { view.facingRight = dx > 0 }
            }
        } else if !active {
            view.facingRight = mouse.x > pos.x
        } else {
            view.facingRight = true  // face the user while busy
        }

        let ex = max(-1, min(1, (mouse.x - pos.x) / 130))
        let ey = max(-1, min(1, (mouse.y - pos.y - 60) / 130))
        view.eyeOffset = CGPoint(x: ex, y: ey)

        blinkTimer -= Int(tickScale.rounded())
        if blinkTimer <= 0 {
            view.blink = min(1, view.blink + 0.34)
            if view.blink >= 1 { blinkTimer = Int.random(in: 60...220); view.blink = 0 }
        }

        place()
        if view.sprite == nil {
            // The drawn art animates continuously, but when the pet is just
            // sitting there nobody can tell 10fps from 30fps — and it is the
            // difference between a few percent of a core and none.
            view.needsDisplay = true
        } else {
            // sprite frames change every few ticks; redraw only then
            let signature =
                "\(view.spriteFrame)|\(view.pose)|\(view.held)|"
                + "\(Int(pos.x))|\(Int(pos.y))|\(view.flashLabel ?? "")"
            if signature != lastSpriteSignature {
                lastSpriteSignature = signature
                view.needsDisplay = true
            }
        }
        sinceSave += dt
        if sinceSave >= 5 { sinceSave = 0; savePos() }
        setLoopRate(desiredLoopRate())
    }
}
