//  AppDelegate+Updates.swift
//  Desktop Pet
//
//  Checking GitHub for a newer release, and installing it in place. The app
//  downloads the release zip itself — so it never gains a quarantine
//  attribute — verifies its checksum and version, swaps the bundle, and
//  relaunches. Nothing installs without a click.

import Cocoa
import CryptoKit

/// What the latest GitHub release offers the updater.
struct ReleaseInfo {
    let tag: String
    /// The DesktopPet-x.y.z.zip asset, when the release has one.
    let zipURL: URL?
    /// The zip's SHA-256, published in the release notes. The updater
    /// refuses to install without it.
    let sha256: String?
}

extension AppDelegate {

    static let releasesPage = URL(string: "https://github.com/ryccoatika/PetProject/releases")!
    private static let latestRelease = URL(
        string: "https://api.github.com/repos/ryccoatika/PetProject/releases/latest")!

    /// "v1.2.3" (or "1.2.3") is newer than "1.2.2". Anything unparseable is
    /// not newer, so a bad tag can never nag.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            let bare = s.hasPrefix("v") ? String(s.dropFirst()) : s
            return bare.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(tag)
        let b = parts(current)
        guard !a.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The latest release — tag, zip asset and checksum — off the main thread.
    func fetchLatestRelease(_ done: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        var request = URLRequest(url: Self.latestRelease, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { return done(.failure(error)) }
            guard let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String
            else {
                return done(
                    .failure(
                        NSError(
                            domain: "pet", code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Unexpected answer from GitHub."
                            ])))
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String ?? "").hasSuffix(".zip") }
            let zipURL = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:))
            // the checksum is the one 64-hex token in the release notes
            let body = json["body"] as? String ?? ""
            let sha = body.range(of: "[a-fA-F0-9]{64}", options: .regularExpression)
                .map { String(body[$0]).lowercased() }
            done(.success(ReleaseInfo(tag: tag, zipURL: zipURL, sha256: sha)))
        }.resume()
    }

    @objc func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPage)
    }

    /// The About button and the menu's update row: spin in place while
    /// GitHub answers, then say what it said. About stays open the whole
    /// time.
    @objc func checkForUpdates() {
        aboutCheckButton?.isEnabled = false
        aboutCheckButton?.title = "Checking…"
        fetchLatestRelease { result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.aboutCheckButton?.isEnabled = true
                self.aboutCheckButton?.title = "Check for Updates"
                self.showUpdateResult(result)
            }
        }
    }

    /// As a sheet on the About window when it is open, else its own dialog.
    private func showUpdateResult(_ result: Result<ReleaseInfo, Error>) {
        let alert = NSAlert()
        var offer: ReleaseInfo?
        switch result {
        case .success(let release) where Self.isNewer(release.tag, than: Build.version):
            rememberAvailableUpdate(release.tag)
            alert.messageText = "Pet \(release.tag) is available"
            if release.zipURL != nil && release.sha256 != nil {
                alert.informativeText =
                    "You have \(Build.version). Install Update downloads it, verifies it "
                    + "and relaunches — settings and skins stay put."
                alert.addButton(withTitle: "Install Update")
                offer = release
            } else {
                // an old release without the zip or checksum: manual it is
                alert.informativeText =
                    "You have \(Build.version). The new version is on the releases page."
                alert.addButton(withTitle: "Open Releases Page")
            }
            alert.addButton(withTitle: "Later")
        case .success:
            rememberAvailableUpdate(nil)
            alert.messageText = "You're up to date"
            alert.informativeText = "Pet \(Build.version) is the latest release."
        case .failure(let error):
            alert.messageText = "Could not check for updates"
            alert.informativeText = error.localizedDescription
        }
        let react: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            if let offer {
                self?.installUpdate(offer)
            } else if case .success(let release) = result,
                Self.isNewer(release.tag, than: Build.version)
            {
                self?.openReleasesPage()
            }
        }
        if let window = aboutWindow, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: react)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            react(alert.runModal())
        }
    }

    // MARK: installing

    /// Download, verify, swap and relaunch. Every step must succeed before
    /// anything is touched; a failure leaves the current app exactly as it
    /// was and says what went wrong.
    func installUpdate(_ release: ReleaseInfo) {
        guard let zipURL = release.zipURL, let sha = release.sha256 else { return }
        aboutCheckButton?.isEnabled = false
        aboutCheckButton?.title = "Updating…"
        Log.info("update: installing \(release.tag) from \(zipURL.absoluteString)")
        flash("updating…")

        URLSession.shared.downloadTask(with: zipURL) { file, _, error in
            let outcome: Result<Void, Error>
            if let file {
                outcome = Result {
                    try Self.applyUpdate(zip: file, sha256: sha, tag: release.tag)
                }
            } else {
                outcome = .failure(
                    error
                        ?? NSError(
                            domain: "pet", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "The download failed."]))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.aboutCheckButton?.isEnabled = true
                self.aboutCheckButton?.title = "Check for Updates"
                switch outcome {
                case .success:
                    Log.info("update: \(release.tag) verified and in place, relaunching")
                    self.relaunch()
                case .failure(let error):
                    Log.error("update: \(error.localizedDescription)")
                    self.showUpdateFailure(error)
                }
            }
        }.resume()
    }

    /// The verified swap, off the main thread. Throws rather than limping on.
    private static func applyUpdate(zip: URL, sha256: String, tag: String) throws {
        func bail(_ message: String) -> NSError {
            NSError(domain: "pet", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
        }

        // 1. checksum: the download must be byte-for-byte what was published
        let data = try Data(contentsOf: zip)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else {
            throw bail("The download did not match the published checksum.")
        }

        // 2. unpack next to nothing that matters
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("pet-update-\(tag)")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw bail("The download would not unpack.") }
        let newApp = work.appendingPathComponent("Pet.app")
        let newBinary = newApp.appendingPathComponent("Contents/MacOS/Pet")
        guard fm.fileExists(atPath: newBinary.path) else {
            throw bail("The download did not contain Pet.app.")
        }

        // 3. the new binary must run and be the version the tag promised
        let probe = Process()
        probe.executableURL = newBinary
        probe.arguments = ["--version"]
        let out = Pipe()
        probe.standardOutput = out
        try probe.run()
        probe.waitUntilExit()
        let printed =
            String(
                data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let bare = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard probe.terminationStatus == 0, printed.contains(bare) else {
            throw bail("The downloaded app reported the wrong version.")
        }

        // 4. swap: old aside, new in place; put the old one back on failure
        let current = Bundle.main.bundleURL
        let aside = work.appendingPathComponent("Pet.app.previous")
        try fm.moveItem(at: current, to: aside)
        do {
            try fm.moveItem(at: newApp, to: current)
        } catch {
            try? fm.moveItem(at: aside, to: current)
            throw error
        }
    }

    /// Start this bundle again once this process has gone — the tail end of
    /// an update, and the menu's Restart Pet.
    func relaunch() {
        let path = Bundle.main.bundleURL.path
        let handoff = Process()
        handoff.executableURL = URL(fileURLWithPath: "/bin/sh")
        handoff.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(path)\""]
        try? handoff.run()
        NSApp.terminate(nil)
    }

    private func showUpdateFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not install the update"
        alert.informativeText =
            error.localizedDescription + "\nNothing was changed — the releases page still works."
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Later")
        let react: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertFirstButtonReturn { self?.openReleasesPage() }
        }
        if let window = aboutWindow, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: react)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            react(alert.runModal())
        }
    }

    // MARK: the quiet check

    /// The quiet check on launch: at most once a day, and a newer version
    /// only becomes a menu row — never a dialog, never a download.
    func checkForUpdatesQuietly() {
        // what an earlier launch already found, so the row survives a restart
        if let stored = Prefs.store.string(forKey: "petUpdateAvailable"),
            Self.isNewer(stored, than: Build.version)
        {
            updateAvailable = stored
            buildMenu()  // the menu was built before this ran
        } else {
            Prefs.store.removeObject(forKey: "petUpdateAvailable")
        }

        let last = Prefs.store.double(forKey: "petUpdateChecked")
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        fetchLatestRelease { result in
            guard case .success(let release) = result else { return }  // try again tomorrow
            DispatchQueue.main.async { [weak self] in
                Prefs.store.set(Date().timeIntervalSince1970, forKey: "petUpdateChecked")
                self?.rememberAvailableUpdate(
                    Self.isNewer(release.tag, than: Build.version) ? release.tag : nil)
            }
        }
    }

    private func rememberAvailableUpdate(_ tag: String?) {
        if let tag, tag != updateAvailable { Log.info("update available: \(tag)") }
        updateAvailable = tag
        if let tag {
            Prefs.store.set(tag, forKey: "petUpdateAvailable")
        } else {
            Prefs.store.removeObject(forKey: "petUpdateAvailable")
        }
        buildMenu()
    }
}
