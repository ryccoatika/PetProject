//  AppDelegate.swift
//  Desktop Pet
//
//  App lifecycle: the window, the loop, and shared state.

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The drawn art needs a small window; a sprite cell wants 210x240 so it
    /// can be blitted 1:1. Rasterising the drawn pet into the larger window
    /// costs measurably more, so the window follows the art.
    static let vectorSize = NSSize(width: 170, height: 165)
    static let spriteSize = NSSize(width: 210, height: 240)
    /// The window's size, which is the design size times `artScale`.
    var size = AppDelegate.vectorSize

    /// How big the user wants the pet, 0.5x to 2x.
    static let scaleRange: ClosedRange<CGFloat> = 0.5...2
    var artScale: CGFloat = 1
    var window: NSWindow!
    var view: PetView!
    var statusItem: NSStatusItem?
    var trayHidden = false  // menu bar icon hidden; CLI brings it back
    var timer: Timer?

    /// Activity file the pet reacts to: one line, EVENT|TOOL|EPOCH.
    /// Anything can write it — the Claude Code plugin is just one producer.
    var stateURL: URL { SkinStore.configDir.appendingPathComponent("state") }
    var lastStamp: TimeInterval = 0
    var event = "", tool = "", lastTool = ""
    var eventAge: TimeInterval = 9999
    var idleSince = Date()
    var pos = CGPoint.zero
    var chaseWhenIdle = false
    /// Idle antics: a bored pet wanders, waves or sulks on its own.
    var anticsEnabled = true
    /// The act in progress — .waving, .angry, or .running while wandering.
    var idleAct: Pose?
    var idleActUntil = Date.distantPast
    /// Quiet seconds at which the next antic fires; 0 means unscheduled.
    var nextActQuiet: TimeInterval = 0
    var wanderTarget: CGPoint?
    /// With antics on, sleep comes later so the pet has time to be bored.
    let anticsSleepAt: TimeInterval = 150
    var dragging = false
    var isActive = false  // Claude is thinking / running a tool
    var lastTrack: SpritePet.Track = .idle
    var lastSpriteSignature = ""
    var lastMouseMove = Date.distantPast
    var lastMousePoint = CGPoint.zero
    var hidden = false  // pet hidden from screen via the menu
    var skins: [Skin] = []
    var sprites: [SpritePet] = []
    var skinErrors: [String] = []
    var skinMenu = NSMenu()
    var pluginMenu = NSMenu()
    var sizeMenu = NSMenu()
    var iconMenu = NSMenu()
    var appearanceMenu = NSMenu()
    var behaviorMenu = NSMenu()
    /// A newer release's tag, when the quiet launch check found one.
    var updateAvailable: String?
    /// The About window and its update controls; kept so a second About
    /// brings the same window forward and the spinner can be driven.
    var aboutWindow: NSWindow?
    var aboutCheckButton: NSButton?
    var aboutSpinner: NSProgressIndicator?
    /// The activity-bubble stack above the pet's head.
    var bubbleWindow: NSWindow?
    var bubbleView: BubbleView?
    var bubblesEnabled = true
    var bubbleSignature = ""
    var bubbleItem: NSMenuItem!
    var sinceBubbleRead: Double = 0
    /// Live sessions, re-read on a slow tick and shared by the bubbles, the
    /// badge and the pose.
    var liveSessions: [AgentSession] = []

    /// Chime when a session starts waiting for you. Off by default.
    var chimeEnabled = false
    var chimeItem: NSMenuItem!
    let chimeSoundName = "Submarine"  // a built-in macOS alert sound
    var lastWaitingSessions: Set<String> = []
    var bubbleWindowSeenOnce = false

    /// Which agent session drives the pose. Empty means auto (most urgent).
    var pinnedSession = ""
    var followMenu = NSMenu()
    /// The menu bar badge tracks live sessions and whether any needs you.
    var lastBadge = ""
    /// The sprite track+frame last drawn into the menu bar, so it only
    /// redraws when the frame actually changes.
    var lastTraySignature = ""

    /// Streaks: consecutive tool successes lift the celebration; repeated
    /// failures earn a longer, glummer failed pose.
    var successStreak = 0
    var failureStreak = 0
    var lastStreakStamp: TimeInterval = 0

    /// Toss physics: velocity carried from a flick, integrated until settled.
    var throwVelocity = CGVector.zero
    var throwing = false
    var dragSamples: [(t: TimeInterval, p: CGPoint)] = []
    var sizeSlider: NSSlider?
    var sizeReadout: NSTextField?
    var sizeResetItem: NSMenuItem?
    let mainMenu = NSMenu()
    var statusRow: NSMenuItem!
    var visItem: NSMenuItem!
    var chaseItem: NSMenuItem!
    var anticsItem: NSMenuItem!
    var cliItem: NSMenuItem!
    /// Whether `pet` resolves in the user's own shell. Assume it does until
    /// the check says otherwise, so the warning never flashes up wrongly.
    var cliReachable = true
    var flashText = ""  // brief pill message after a toggle
    var flashUntil = Date.distantPast
    var savedPos = CGPoint.zero  // last position written to preferences
    var blinkTimer = 60
    var tick = 0
    /// The loop runs fast only when something is actually moving.
    let fps: Double = 30  // animation reference rate
    var currentFPS: Double = 0
    /// Scales per-tick animation so it looks the same at any loop rate.
    var tickScale: Double { fps / max(currentFPS, 1) }
    var sinceStateRead: Double = 0
    var sinceSave: Double = 0
    var sinceSpriteFrame: Double = 0

    /// Last origin handed to the window server, so an unmoved pet costs
    /// nothing. See `place()`.
    var placedAt = CGPoint(x: CGFloat.infinity, y: CGFloat.infinity)

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hidden = Prefs.store.bool(forKey: "petHidden")  // before the window is shown
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        view = PetView(frame: NSRect(origin: .zero, size: size))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        window.contentView = view
        if !hidden { window.orderFrontRegardless() }

        let d = Prefs.store
        chaseWhenIdle = d.bool(forKey: "petChase")
        bubblesEnabled = !d.bool(forKey: "petBubblesHidden")
        chimeEnabled = d.bool(forKey: "petChime")
        anticsEnabled = !d.bool(forKey: "petAnticsOff")
        pinnedSession = d.string(forKey: "petFollowSession") ?? ""
        if let saved = d.object(forKey: "petScale") as? Double { artScale = CGFloat(saved) }
        reloadSkins()
        let wanted = d.string(forKey: "petSkin") ?? "tabby"
        if let pet = sprites.first(where: { $0.id == wanted }) {
            view.sprite = pet
        } else {
            view.skin = skins.first { $0.id == wanted } ?? skins[0]
        }
        if d.object(forKey: "petPosX") != nil {
            pos = CGPoint(x: d.double(forKey: "petPosX"), y: d.double(forKey: "petPosY"))
        } else {
            let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            pos = CGPoint(x: f.midX, y: f.midY - size.height / 2)  // centre on first run
        }
        applyWindowSize()
        pos = clampToScreen(pos)
        savePos(force: true)
        view.dragBegin = { [weak self] in self?.dragging = true }
        view.dragMove = { [weak self] origin in
            guard let self else { return }
            self.pos = CGPoint(x: origin.x + self.size.width / 2, y: origin.y)
            self.throwing = false  // grabbing it out of the air stops a throw
            self.view.spin = 0
            self.view.squash = 1
            self.recordDragSample()
            self.place()
        }
        view.dragEnd = { [weak self] in self?.endDrag() }
        view.doubleClick = { [weak self] in self?.toggleChase() }
        place()

        trayHidden = Prefs.store.bool(forKey: "petTrayHidden")
        if !trayHidden { showTray() }

        installCommandLineTool()
        checkCommandLineReachable()
        checkForUpdatesQuietly()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reloadFromPreferences),
            name: Notification.Name(Prefs.reloadNotification), object: nil)
        writeRuntime()

        setLoopRate(fps)
    }
}
