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
        /// The account this reading is for — "default" for plain ~/.claude,
        /// else the claude dir's own suffix (~/.claude-account1 → "account1").
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

    /// ~/.claude → "default", ~/.claude-account1 → "account1", so the badge
    /// labels match the folder names most people already chose for this.
    static func accountLabel(for claudeDir: URL) -> String {
        var name = claudeDir.lastPathComponent
        if name.hasPrefix(".") { name.removeFirst() }
        for prefix in ["claude-", "claude_"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.isEmpty || name == "claude" ? "default" : name
    }

    private static func safeFileName(_ account: String) -> String {
        String(account.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }

    /// One line: sessionPct|sessionResets|weekPct|weekResets|stamp. A field
    /// is empty when Claude Code did not report that window.
    static func write(rateLimits: [String: Any], account: String) {
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
            to: directory.appendingPathComponent(safeFileName(account)), atomically: true,
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
        // "default" first (plain ~/.claude, what almost everyone has), then
        // alphabetically, so the row does not reshuffle from tick to tick.
        return snapshots.sorted {
            ($0.account == "default" ? "" : $0.account)
                < ($1.account == "default" ? "" : $1.account)
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
