//  AppDelegate+Plugins.swift
//  Desktop Pet
//
//  Installing and removing agent plugins from the menu.

import Cocoa

extension AppDelegate {

    @objc func togglePlugin(_ item: NSMenuItem) {
        guard item.tag < HookHost.all.count else { return }
        let host = HookHost.all[item.tag]
        let registered = HookPlugin.isRegistered(host)
        HookPlugin.apply(host, remove: registered)
        populatePluginMenu()
        flash(registered ? "\(host.id) plugin removed" : "\(host.id) plugin added")
    }

    @objc func removeStrayPlugin(_ item: NSMenuItem) {
        guard let dir = item.representedObject as? URL else { return }
        HookPlugin.apply(HookHost.claude.targeting([dir]), remove: true)
        populatePluginMenu()
        flash("removed from \(dir.lastPathComponent)")
    }
}
