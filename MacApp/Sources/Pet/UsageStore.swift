//  UsageStore.swift
//  Desktop Pet
//
//  Claude's own rate-limit usage — the numbers /usage shows — read from
//  Claude Code's statusLine payload (hooks never receive them) and written
//  to one small file per Claude account, so running several accounts at
//  once (~/.claude, ~/.claude-account1, …) shows all of them rather than
//  the last one to write clobbering the rest. See `pet statusline` in
//  CLI+Usage.swift for where the file is written.

import Foundation

enum UsageStore {
    static var directory: URL { SkinStore.configDir.appendingPathComponent("usage") }

    struct Snapshot {
        /// The account's storage key — its config folder's own name, so it
        /// is always unique regardless of what the folder is called. Use
        /// `label` for what to show on screen.
        let account: String
        /// 0–100, Anthropic's own rolling 5-hour window — what /usage calls
        /// "Current session". Not this app's idea of an agent session.
        let sessionPercent: Double?
        let sessionResetsAt: TimeInterval?
        /// 0–100, the 7-day window across every Claude model.
        let weekPercent: Double?
        let weekResetsAt: TimeInterval?
        let stamp: TimeInterval

        var age: TimeInterval { Date().timeIntervalSince1970 - stamp }
        /// The friendly caption for the badge and `pet usage`.
        var label: String { UsageStore.displayLabel(forKey: account) }
        /// The more urgent of the two — what a glance most needs to know.
        var worstPercent: Double? {
            switch (sessionPercent, weekPercent) {
            case (let s?, let w?): return max(s, w)
            case (let s?, nil): return s
            case (nil, let w?): return w
            default: return nil
            }
        }
    }

    /// A stale account — its Claude Code closed, or it was only ever tried
    /// once — is dropped rather than shown frozen forever.
    static let staleAfter: TimeInterval = 3600

    /// The filename an account's readings live under: its config folder's
    /// own name (~/.claude-account1 → "claude-account1"), filesystem-safe.
    /// Always unique — two different folders can never collide, however
    /// they are named — unlike a shortened display label, which is only
    /// cosmetic.
    static func accountKey(for claudeDir: URL) -> String {
        var name = claudeDir.lastPathComponent
        if name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "claude" }
        return String(name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }

    /// A friendlier caption derived from the stored key: "claude" (plain
    /// ~/.claude) → "default", a "claude" prefix followed by "-" or "_" is
    /// dropped so "claude-account1" → "account1" and "claude1" → "1". Purely
    /// cosmetic — two keys that happen to shorten to the same word (
    /// "claude-work" and "claude_work", say) still keep separate readings;
    /// only their caption would coincide, which no real setup does by
    /// accident.
    static func displayLabel(forKey key: String) -> String {
        guard key != "claude" else { return "default" }
        var name = key
        if name.hasPrefix("claude") {
            name.removeFirst("claude".count)
            while name.hasPrefix("-") || name.hasPrefix("_") { name.removeFirst() }
        }
        return name.isEmpty ? "default" : name
    }

    /// One line: sessionPct|sessionResets|weekPct|weekResets|stamp. A field
    /// is empty when Claude Code did not report that window.
    static func write(rateLimits: [String: Any], claudeDir: URL) {
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
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path, isDirectory: &isDir), !isDir.boolValue {
            try? fm.removeItem(at: directory)  // the old single-file format, single-account only
        }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? line.write(
            to: directory.appendingPathComponent(accountKey(for: claudeDir)), atomically: true,
            encoding: .utf8)
    }

    /// Every account with a reading, fresh or not — callers filter by `age`
    /// as they see fit. Files untouched for a week are cleaned up in passing.
    static func readAll() -> [Snapshot] {
        guard
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        var snapshots: [Snapshot] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let file = directory.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(
                separatedBy: "|")
            guard parts.count >= 5, let stamp = TimeInterval(parts[4]) else { continue }
            if Date().timeIntervalSince1970 - stamp > 7 * 86400 {
                try? FileManager.default.removeItem(at: file)  // long-dead account
                continue
            }
            snapshots.append(
                Snapshot(
                    account: name, sessionPercent: Double(parts[0]),
                    sessionResetsAt: TimeInterval(parts[1]), weekPercent: Double(parts[2]),
                    weekResetsAt: TimeInterval(parts[3]), stamp: stamp))
        }
        // "claude" (plain ~/.claude, what almost everyone has) first, then
        // alphabetically by key, so the row does not reshuffle from tick to
        // tick even if two accounts share a shortened display label.
        return snapshots.sorted {
            ($0.account == "claude" ? "" : $0.account)
                < ($1.account == "claude" ? "" : $1.account)
        }
    }

    static func humanReset(_ epoch: TimeInterval?) -> String? {
        guard let epoch else { return nil }
        let seconds = epoch - Date().timeIntervalSince1970
        guard seconds > 0 else { return nil }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}
