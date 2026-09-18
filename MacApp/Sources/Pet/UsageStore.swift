//  UsageStore.swift
//  Desktop Pet
//
//  Claude's own rate-limit usage — the numbers /usage shows — read from
//  Claude Code's statusLine payload (hooks never receive them) and written
//  to a small file the app polls. See `pet statusline` in CLI+Usage.swift
//  for where the file is written.

import Foundation

enum UsageStore {
    static var file: URL { SkinStore.configDir.appendingPathComponent("usage") }

    struct Snapshot {
        /// 0–100, Anthropic's own rolling 5-hour window — what /usage calls
        /// "Current session". Not this app's idea of an agent session.
        let sessionPercent: Double?
        let sessionResetsAt: TimeInterval?
        /// 0–100, the 7-day window across every Claude model.
        let weekPercent: Double?
        let weekResetsAt: TimeInterval?
        let stamp: TimeInterval

        var age: TimeInterval { Date().timeIntervalSince1970 - stamp }
    }

    /// One line: sessionPct|sessionResets|weekPct|weekResets|stamp. A field
    /// is empty when Claude Code did not report that window.
    static func write(rateLimits: [String: Any]) {
        func window(_ key: String) -> (Double?, TimeInterval?) {
            guard let w = rateLimits[key] as? [String: Any] else { return (nil, nil) }
            return (w["used_percentage"] as? Double, w["resets_at"] as? TimeInterval)
        }
        let (sessionPct, sessionResets) = window("five_hour")
        let (weekPct, weekResets) = window("seven_day")
        guard sessionPct != nil || weekPct != nil else { return }  // nothing worth keeping

        func field(_ d: Double?) -> String { d.map { String($0) } ?? "" }
        let line =
            "\(field(sessionPct))|\(field(sessionResets))|\(field(weekPct))|\(field(weekResets))"
            + "|\(Int(Date().timeIntervalSince1970))\n"
        try? FileManager.default.createDirectory(
            at: SkinStore.configDir, withIntermediateDirectories: true)
        try? line.write(to: file, atomically: true, encoding: .utf8)
    }

    static func read() -> Snapshot? {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(
            separatedBy: "|")
        guard parts.count >= 5, let stamp = TimeInterval(parts[4]) else { return nil }
        return Snapshot(
            sessionPercent: Double(parts[0]), sessionResetsAt: TimeInterval(parts[1]),
            weekPercent: Double(parts[2]), weekResetsAt: TimeInterval(parts[3]), stamp: stamp)
    }

    /// A stale snapshot — Claude Code closed, or never a Pro/Max plan — is
    /// worse than none: the badge would freeze on a number from hours ago.
    static let staleAfter: TimeInterval = 3600

    static func humanReset(_ epoch: TimeInterval?) -> String? {
        guard let epoch else { return nil }
        let seconds = epoch - Date().timeIntervalSince1970
        guard seconds > 0 else { return nil }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}
