//  main.swift
//  Desktop Pet
//
//  Entry point. Decides between the command line tool, an offscreen render,
//  and the app itself, then hands over.
//
//  Everything else lives in Sources/.

import Cocoa

/// macOS can append a -psn_… process-serial-number argument when launching a
/// bundle, so it never counts as a command.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }

/// Renders write a file and exit; they are not part of the CLI's command set
/// because the build calls them directly.
private func runRenderer(_ name: String, _ rest: [String]) -> Bool {
    guard let out = rest.last, out.lowercased().hasSuffix(".png") else {
        CLI.fail("usage: pet \(name) [size] <file.png>")
    }
    switch name {
    case "dmgbg":
        Renderers.dmgBackground(to: out)
    case "icon":
        Renderers.appIcon(size: rest.compactMap { Int($0) }.first ?? 1024, to: out)
    case "render":
        Renderers.contactSheet(to: out, tracks: rest.contains("--tracks"))
    default:
        return false
    }
    return true
}

if let first = arguments.first {
    let renderers = ["render", "icon", "dmgbg", "--render", "--icon", "--dmgbg"]
    if renderers.contains(first) {
        _ = NSApplication.shared                    // renderers need AppKit up
        let name = first.hasPrefix("--") ? String(first.dropFirst(2)) : first
        if runRenderer(name, Array(arguments.dropFirst())) { exit(0) }
        exit(1)
    }
    CLI.run([CommandLine.arguments[0]] + arguments)
} else if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent != "Pet" {
    // Invoked as `pet` with no arguments: show help. Only the bundle's own
    // executable (Contents/MacOS/Pet, how Finder and `open` launch it) starts
    // the pet itself.
    CLI.help()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
