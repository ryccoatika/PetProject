//  AppDelegate+Updates.swift
//  Desktop Pet
//
//  Checking GitHub for a newer release. Never downloads anything — a newer
//  version is offered as a link to the releases page.

import Cocoa

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

    /// The latest release tag, off the main thread.
    func fetchLatestReleaseTag(_ done: @escaping (Result<String, Error>) -> Void) {
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
            done(.success(tag))
        }.resume()
    }

    @objc func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPage)
    }

    /// The About button: spin in place while GitHub answers, then say what
    /// it said. About stays open the whole time.
    @objc func checkForUpdates() {
        aboutCheckButton?.isEnabled = false
        aboutSpinner?.startAnimation(nil)
        fetchLatestReleaseTag { result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.aboutSpinner?.stopAnimation(nil)
                self.aboutCheckButton?.isEnabled = true
                self.showUpdateResult(result)
            }
        }
    }

    /// As a sheet on the About window when it is open, else its own dialog.
    private func showUpdateResult(_ result: Result<String, Error>) {
        let alert = NSAlert()
        var offersRelease = false
        switch result {
        case .success(let tag) where Self.isNewer(tag, than: Build.version):
            rememberAvailableUpdate(tag)
            alert.messageText = "Pet \(tag) is available"
            alert.informativeText =
                "You have \(Build.version). The new version is on the releases page."
            alert.addButton(withTitle: "Open Releases Page")
            alert.addButton(withTitle: "Later")
            offersRelease = true
        case .success:
            rememberAvailableUpdate(nil)
            alert.messageText = "You're up to date"
            alert.informativeText = "Pet \(Build.version) is the latest release."
        case .failure(let error):
            alert.messageText = "Could not check for updates"
            alert.informativeText = error.localizedDescription
        }
        let react: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if offersRelease && response == .alertFirstButtonReturn {
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

    /// The quiet check on launch: at most once a day, and a newer version
    /// only becomes a menu row — never a dialog.
    func checkForUpdatesQuietly() {
        // what an earlier launch already found, so the row survives a restart
        if let stored = Prefs.store.string(forKey: "petUpdateAvailable"),
            Self.isNewer(stored, than: Build.version)
        {
            updateAvailable = stored
        } else {
            Prefs.store.removeObject(forKey: "petUpdateAvailable")
        }

        let last = Prefs.store.double(forKey: "petUpdateChecked")
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        fetchLatestReleaseTag { result in
            guard case .success(let tag) = result else { return }  // quietly try again tomorrow
            DispatchQueue.main.async { [weak self] in
                Prefs.store.set(Date().timeIntervalSince1970, forKey: "petUpdateChecked")
                self?.rememberAvailableUpdate(
                    Self.isNewer(tag, than: Build.version) ? tag : nil)
            }
        }
    }

    private func rememberAvailableUpdate(_ tag: String?) {
        updateAvailable = tag
        if let tag {
            Prefs.store.set(tag, forKey: "petUpdateAvailable")
        } else {
            Prefs.store.removeObject(forKey: "petUpdateAvailable")
        }
        buildMenu()
    }
}
