//  Log.swift
//  Desktop Pet
//
//  A plain text log at <configDir>/logs/pet.log, so a bug report can come
//  with evidence. Notable events only — never the animation loop — so the
//  file stays small and the cost stays nil.

import Foundation

enum Log {
    static var folder: URL { SkinStore.configDir.appendingPathComponent("logs") }
    static var file: URL { folder.appendingPathComponent("pet.log") }

    /// One rotation: past this size the log becomes pet.log.1 and starts
    /// fresh, so it can never grow without bound.
    private static let rotateAt = 512 * 1024
    private static let queue = DispatchQueue(label: "pet.log", qos: .utility)

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Append one line, off the caller's thread. Never throws, never blocks
    /// the app: a log that cannot be written is quietly not written.
    static func info(_ message: String) {
        let line = "\(stamp.string(from: Date())) [\(Build.version)] \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = try? fm.attributesOfItem(atPath: file.path)[.size] as? Int,
                size > rotateAt
            {
                let old = folder.appendingPathComponent("pet.log.1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: file, to: old)
            }
            if let handle = FileHandle(forWritingAtPath: file.path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                try? line.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    /// The same, for failures — greppable in a report.
    static func error(_ message: String) { info("ERROR " + message) }

    /// Wait for pending lines: for the moment before the process exits.
    static func drain() { queue.sync {} }
}
