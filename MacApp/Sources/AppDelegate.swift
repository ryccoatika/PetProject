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
    var size = AppDelegate.vectorSize
    var window: NSWindow!
    var view: PetView!
    var statusItem: NSStatusItem?
    var trayHidden = false             // menu bar icon hidden; CLI brings it back
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
    var dragging = false
    var isActive = false               // Claude is thinking / running a tool
    var lastTrack: SpritePet.Track = .idle
    var lastSpriteSignature = ""
    var lastMouseMove = Date.distantPast
    var lastMousePoint = CGPoint.zero
    var hidden = false                 // pet hidden from screen via the menu
    var skins: [Skin] = []
    var sprites: [SpritePet] = []
    var skinErrors: [String] = []
    var skinMenu = NSMenu()
    var pluginMenu = NSMenu()
    let mainMenu = NSMenu()
    var statusRow: NSMenuItem!
    var visItem: NSMenuItem!
    var chaseItem: NSMenuItem!
    var cliItem: NSMenuItem!
    /// Whether `pet` resolves in the user's own shell. Assume it does until
    /// the check says otherwise, so the warning never flashes up wrongly.
    var cliReachable = true
    var flashText = ""                 // brief pill message after a toggle
    var flashUntil = Date.distantPast
    var savedPos = CGPoint.zero        // last position written to preferences
    var blinkTimer = 60
    var tick = 0
    /// The loop runs fast only when something is actually moving.
    let fps: Double = 30                 // animation reference rate
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
        hidden = Prefs.store.bool(forKey: "petHidden")   // before the window is shown
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        view = PetView(frame: NSRect(origin: .zero, size: size))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = view
        if !hidden { window.orderFrontRegardless() }

        let d = Prefs.store
        chaseWhenIdle = d.bool(forKey: "petChase")
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
            pos = CGPoint(x: f.midX, y: f.midY - size.height / 2)   // centre on first run
        }
        applyWindowSize()
        pos = clampToScreen(pos)
        savePos(force: true)
        view.dragBegin = { [weak self] in self?.dragging = true }
        view.dragMove  = { [weak self] origin in
            guard let self else { return }
            self.pos = CGPoint(x: origin.x + self.size.width / 2, y: origin.y)
            self.place()
        }
        view.dragEnd   = { [weak self] in self?.endDrag() }
        view.doubleClick = { [weak self] in self?.toggleChase() }
        place()

        trayHidden = Prefs.store.bool(forKey: "petTrayHidden")
        if !trayHidden { showTray() }

        installCommandLineTool()
        checkCommandLineReachable()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reloadFromPreferences),
            name: Notification.Name(Prefs.reloadNotification), object: nil)
        writeRuntime()

        setLoopRate(fps)
    }
}
