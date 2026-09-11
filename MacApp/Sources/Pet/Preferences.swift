//  Preferences.swift
//  Desktop Pet
//
//  Preferences shared by the app and the CLI.

import Cocoa

enum Prefs {
    static let domain = "local.desktop.pet"
    static let reloadNotification = "local.desktop.pet.reload"

    /// Always addressed by suite name: the CLI runs from the same binary but
    /// not necessarily as the bundled app, so .standard could differ.
    static var store: UserDefaults { UserDefaults(suiteName: domain) ?? .standard }

    /// Pick up writes made by another process.
    static func refresh() { CFPreferencesAppSynchronize(domain as CFString) }

    static func notifyRunningApp() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(reloadNotification), object: nil, userInfo: nil,
            deliverImmediately: true)
    }
}

// MARK: - Skins (loaded from .petskin resource files, never hardcoded)
