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
        if dragging || throwing || view.held || view.pose == .running { return 30 }
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
            + "antics=\(anticsEnabled ? 1 : 0) "
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
        anticsEnabled = !d.bool(forKey: "petAnticsOff")
        if !anticsEnabled { endIdleAct() }
        bubblesEnabled = !d.bool(forKey: "petBubblesHidden")
        if !bubblesEnabled { hideBubbles() }
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
        launchThrowIfFlicked()
        if !throwing {
            pos = clampToScreen(pos)
            savePos()
            place()
        }
        refreshMenu()
    }

    /// Remember where the pet is and when, for a moment, so a release can
    /// tell a flick from a gentle drop.
    func recordDragSample() {
        let now = Date().timeIntervalSince1970
        dragSamples.append((now, pos))
        dragSamples = dragSamples.filter { now - $0.t < 0.12 }
    }

    /// A quick flick on release throws the pet; a slow drop just leaves it.
    /// Works with chase on too — the pet sails, lands, then chase resumes and
    /// it heads back to the cursor.
    func launchThrowIfFlicked() {
        defer { dragSamples.removeAll() }
        guard let first = dragSamples.first, let last = dragSamples.last, last.t > first.t
        else { return }
        let dt = CGFloat(last.t - first.t)
        let vx = (last.p.x - first.p.x) / dt
        let vy = (last.p.y - first.p.y) / dt
        let speed = hypot(vx, vy)  // pixels per second, before any cap
        guard speed > 400 else { return }  // below this it is a drop
        // per-frame velocity, capped so a hard flick stays on screen
        let perFrame = CGFloat(fps)
        throwVelocity = CGVector(
            dx: max(-60, min(60, vx / perFrame)), dy: max(-60, min(60, vy / perFrame)))
        throwing = true
        view.spin = 0
        view.squash = 1
        // a cheeky readout, scaled to how hard it was flung
        let shout =
            speed > 3500 ? "🚀 to the moon!" : speed > 2000 ? "wheee!" : "whee!"
        flash("\(shout)  \(Int(speed)) px/s")
    }

    /// One step of the toss: gravity, movement, and a damped bounce off the
    /// screen edges. Settles when it is slow and on the floor.
    func throwStep() {
        let screen =
            NSScreen.screens.first { $0.frame.contains(pos) } ?? NSScreen.main
            ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let floor = f.minY + 4
        let ceiling = f.maxY - size.height
        let leftX = f.minX + 50, rightX = f.maxX - 50

        throwVelocity.dy -= 2.6 * tickScale  // gravity
        pos.x += throwVelocity.dx * tickScale
        pos.y += throwVelocity.dy * tickScale

        let ts = CGFloat(tickScale)
        // tumble in the air, faster the faster it flies
        view.spin += throwVelocity.dx * 0.012 * ts
        // ease any squash back out
        view.squash += (1 - view.squash) * 0.25 * ts

        let bounce: CGFloat = 0.55
        func splat() { view.squash = 0.7 }  // compress against whatever it hit
        if pos.x < leftX {
            pos.x = leftX
            throwVelocity.dx = abs(throwVelocity.dx) * bounce
            splat()
        }
        if pos.x > rightX {
            pos.x = rightX
            throwVelocity.dx = -abs(throwVelocity.dx) * bounce
            splat()
        }
        if pos.y > ceiling {
            pos.y = ceiling
            throwVelocity.dy = -abs(throwVelocity.dy) * bounce
            splat()
        }
        if pos.y < floor {
            pos.y = floor
            throwVelocity.dy = -throwVelocity.dy * bounce
            throwVelocity.dx *= 0.7  // friction with the floor
            splat()
        }

        // settled: on the floor, barely moving
        if pos.y <= floor + 1 && hypot(throwVelocity.dx, throwVelocity.dy) < 1.2 {
            throwing = false
            throwVelocity = .zero
            view.spin = 0
            view.squash = 1
            pos = clampToScreen(pos)
            savePos(force: true)
        }
        view.facingRight = throwVelocity.dx >= 0
        place()
    }

    /// Remember where the pet is so it comes back there next launch.
    func savePos(force: Bool = false) {
        guard force || hypot(pos.x - savedPos.x, pos.y - savedPos.y) > 1 else { return }
        savedPos = pos
        let d = Prefs.store
        d.set(Double(pos.x), forKey: "petPosX")
        d.set(Double(pos.y), forKey: "petPosY")
    }

    func applicationWillTerminate(_ n: Notification) {
        savePos()
        Log.info("quitting")
        Log.drain()
    }

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
        placeBubbles()  // the stack rides along
    }

    // MARK: state file

    func readState() {
        guard let raw = try? String(contentsOf: stateURL, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|")
        guard parts.count >= 3, let ts = TimeInterval(parts[2]) else { return }
        let newEvent = parts[0], newTool = parts[1]
        if ts != lastStamp || newEvent != event {
            if ts != lastStamp {
                idleSince = Date()
                // real activity trumps any antic in progress
                endIdleAct()
                nextActQuiet = 0
            }
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
            if anticsEnabled && !hidden {
                boredPose(quiet: quiet)
                return
            }
            if quiet > 25 {
                view.pose = .sleeping; view.zPhase += 0.006 * tickScale
            } else if quiet > 10 && Int(quiet) % 6 < 2 {
                view.pose = .grooming
            } else {
                view.pose = .sitting
            }
        }

        // A rough patch earns a longer, glummer failed pose; a clean run
        // earns a bigger, longer celebration.
        let failWindow: TimeInterval = failureStreak >= 3 ? 12 : 6
        let celebrateWindow: TimeInterval = successStreak >= 8 ? 4 : 2.4

        switch event {
        case "PostToolUseFailure" where eventAge < failWindow,
            "StopFailure" where eventAge < failWindow:
            view.pose = .failed
            view.label = failureStreak >= 3 ? "having a rough time" : "failed"
        case "Notification" where !stale, "PermissionRequest" where !stale:
            view.pose = .alert; view.label = "needs you"
        case "PreToolUse" where !stale:
            view.pose = .working; view.label = lastTool.isEmpty ? "working" : lastTool
        case "PostToolUse", "UserPromptSubmit":
            if stale { idlePose() } else { view.pose = .thinking; view.label = "thinking" }
        case "Stop" where eventAge < celebrateWindow:
            view.pose = .celebrate
            view.label = successStreak >= 8 ? "on a roll!" : "done"
        default:
            idlePose()
        }
    }

    // MARK: idle antics

    /// A bored pet does something on its own now and then: wanders a few
    /// steps, waves at the user, or gets grumpy about being ignored. Sleep
    /// still wins in the end, so overnight the loop stays at its slow rates.
    func boredPose(quiet: TimeInterval) {
        if quiet > anticsSleepAt {
            endIdleAct()
            view.pose = .sleeping
            view.zPhase += 0.006 * tickScale
            return
        }
        if let act = idleAct {
            // A wander ends at its target (or a safety timeout, in case the
            // walk was blocked); a timed act ends when it expires.
            let done =
                act == .running
                ? wanderTarget == nil || Date() >= idleActUntil
                : Date() >= idleActUntil
            if !done {
                // While wandering the movement code sets .running; sitting is
                // only the fallback for the final step onto the target.
                view.pose = act == .running ? .sitting : act
                return
            }
            endIdleAct()
            nextActQuiet = quiet + .random(in: 9...24)
        }
        if nextActQuiet < 8 { nextActQuiet = quiet + .random(in: 6...16) }  // first boredom
        if quiet >= nextActQuiet {
            startIdleAct(quiet: quiet)
            return
        }
        if quiet > 10 && Int(quiet) % 6 < 2 {
            view.pose = .grooming
        } else {
            view.pose = .sitting
        }
    }

    /// Pick the next antic. The longer it has been ignored, the likelier it
    /// is to sulk; with chase on the pet already walks, so it never wanders.
    func startIdleAct(quiet: TimeInterval) {
        let grumpy = quiet > 60
        let roll = Double.random(in: 0..<1)
        let wanderShare = chaseWhenIdle ? 0.0 : 0.4
        if roll < wanderShare {
            idleAct = .running
            wanderTarget = randomWanderPoint()
            // long enough to cross the screen, then give up on a blocked walk
            let w = wanderTarget ?? pos
            let dist = hypot(w.x - pos.x, w.y - pos.y)
            idleActUntil = Date().addingTimeInterval(Double(dist) / 280 + 4)
            view.pose = .sitting
        } else if roll < wanderShare + (grumpy ? 0.2 : 0.35) {
            idleAct = .waving
            idleActUntil = Date().addingTimeInterval(.random(in: 2.2...3.4))
            view.pose = .waving
        } else {
            idleAct = .angry
            idleActUntil = Date().addingTimeInterval(.random(in: 2.4...4))
            view.pose = .angry
        }
    }

    func endIdleAct() {
        idleAct = nil
        wanderTarget = nil
    }

    /// A stroll target anywhere on the current screen, at least a real walk
    /// away — never a two-pixel shuffle against an edge.
    func randomWanderPoint() -> CGPoint {
        let screen =
            NSScreen.screens.first { $0.frame.contains(pos) } ?? NSScreen.main
            ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let ceiling = max(f.minY + 4, f.maxY - size.height)
        for _ in 0..<4 {
            let p = CGPoint(
                x: CGFloat.random(in: (f.minX + 60)...(f.maxX - 60)),
                y: CGFloat.random(in: (f.minY + 4)...ceiling))
            if hypot(p.x - pos.x, p.y - pos.y) > 150 { return clampToScreen(p) }
        }
        // a small screen or unlucky rolls: head for the far side
        let far = pos.x < f.midX ? f.maxX - 60 : f.minX + 60
        return clampToScreen(CGPoint(x: far, y: pos.y))
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
            sinceBubbleRead += dt
            if sinceBubbleRead >= 0.5 {
                sinceBubbleRead = 0
                liveSessions = SessionStore.read()
                chimeIfNewlyWaiting(liveSessions)  // a chime is useful even when hidden
                refreshBadge(liveSessions)
            }
            driveFromSession()
            updatePose()
            isActive = [.working, .thinking, .alert, .celebrate, .failed].contains(view.pose)
            hideBubbles()
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
        var hovering = false
        if !dragging {
            let local = NSPoint(
                x: mouseNow.x - window.frame.minX, y: mouseNow.y - window.frame.minY)
            hovering = view.grabRect.contains(local)
            if window.ignoresMouseEvents == hovering { window.ignoresMouseEvents = !hovering }
        }

        if dragging {  // user is holding it: no autonomy, run the way it is pulled
            let dx = pos.x - lastDragX
            if abs(dx) > 1 { view.facingRight = dx > 0 }
            lastDragX = pos.x
            view.phase += 0.3
            advanceSprite()
            view.needsDisplay = true
            return
        }

        if throwing {  // sailing through the air after a flick
            view.pose = .running  // legs out, mid-flight
            view.label = nil
            view.phase += 0.3 * tickScale
            throwStep()
            advanceSprite()
            view.needsDisplay = true
            setLoopRate(30)
            return
        }

        if sinceStateRead >= 0.1 { sinceStateRead = 0; readState() } else { eventAge += dt }

        sinceBubbleRead += dt
        if sinceBubbleRead >= 0.5 {
            sinceBubbleRead = 0
            liveSessions = SessionStore.read()
            updateBubbles()
        }
        driveFromSession()
        updatePose()

        // A hover gets a little jump for its trouble, whatever it was doing.
        if hovering {
            view.pose = .celebrate
            view.label = nil
        }

        let active = [.working, .thinking, .alert, .celebrate, .failed].contains(view.pose)
        isActive = active
        advanceSprite()
        view.flashLabel = Date() < flashUntil ? flashText : nil
        view.phase += (active ? 0.3 : 0.07) * tickScale
        let hopHeight: CGFloat = successStreak >= 8 ? 24 : 16
        view.hop = view.pose == .celebrate ? abs(sin(view.phase * 1.9)) * hopHeight : 0

        // The pet has no home: it stays wherever it was last left, and only
        // walks when chasing is on and Claude is idle.
        var target = pos
        let mouse = NSEvent.mouseLocation
        if chaseWhenIdle && !active {
            let m = CGPoint(x: mouse.x, y: mouse.y - 40)
            if hypot(m.x - pos.x, m.y - pos.y) > 46 { target = m }
        }
        if let w = wanderTarget, !active {  // a bored stroll to nowhere much
            if hypot(w.x - pos.x, w.y - pos.y) < 8 { wanderTarget = nil } else { target = w }
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
        animateTrayIfNeeded()  // the menu bar icon follows a sprite skin
        sinceSave += dt
        if sinceSave >= 5 { sinceSave = 0; savePos() }
        setLoopRate(desiredLoopRate())
    }
}
