//  UsageStore.swift
//  Desktop Pet
//
//  Rate-limit usage for the badge below the pet: a rolling short window and
//  a longer one, one small file per account, so running several accounts of
//  the same agent at once (~/.claude, ~/.claude-account1, …) shows all of
//  them rather than the last one to write clobbering the rest.
//
//  Claude Code pushes its numbers to `pet statusline` (see CLI+Usage.swift);
//  Codex has no equivalent, so `pet` polls its own session files instead
//  (see CodexUsage.swift). Both write through the same `write(...)` here,
//  which is why this file knows nothing about either agent's own format.

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
        /// The friendly caption for the badge and `pet usage` — the config
        /// folder's own name with a leading agent prefix ("claude"/"codex")
        /// trimmed, so "claude-account1" and "codex-account1" both read
        /// simply as "account1".
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
    static func accountKey(for configDir: URL) -> String {
        var name = configDir.lastPathComponent
        if name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "config" }
        return String(name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }

    /// The agents whose config folders can end up in the same badge — the
    /// prefix a key may start with, and the name to show for it. A bare
    /// ~/.claude and a bare ~/.codex are both extremely common at once, so
    /// the agent name always stays in the caption rather than both
    /// collapsing to the same "default" — collapsing them was a real bug,
    /// not a hypothetical one: the first time Codex usage was added
    /// alongside Claude's, both showed up captioned "default" with no way
    /// to tell them apart.
    private static let agents: [(prefix: String, name: String)] = [
        ("claude", "Claude"), ("codex", "Codex"),
    ]

    /// True for a bare agent config folder (~/.claude, ~/.codex) — sorts
    /// before any named sub-account.
    static func isDefaultKey(_ key: String) -> Bool { agents.contains { $0.prefix == key } }

    /// A friendlier caption derived from the stored key: a bare agent name
    /// → the agent's own name ("Claude", "Codex"); an agent prefix followed
    /// by "-" or "_" keeps the agent name and appends the rest, so
    /// "claude-account1" → "Claude · account1" and "codex1" → "Codex · 1".
    /// Two keys that happen to shorten to the same suffix ("claude-work" and
    /// "codex-work", say) still keep separate readings and separate
    /// captions — only a literal same-agent, same-suffix collision like
    /// "claude-work" vs "claude_work" would share a caption, which no real
    /// setup does by accident.
    static func displayLabel(forKey key: String) -> String {
        for (prefix, name) in agents where key.hasPrefix(prefix) {
            guard key != prefix else { return name }
            var suffix = key
            suffix.removeFirst(prefix.count)
            while suffix.hasPrefix("-") || suffix.hasPrefix("_") { suffix.removeFirst() }
            return suffix.isEmpty ? name : "\(name) · \(suffix)"
        }
        return key
    }

    /// One line: sessionPct|sessionResets|weekPct|weekResets|stamp. Pass
    /// `nil` for a window the agent did not report; a reading with neither
    /// window is not worth keeping and is silently dropped.
    static func write(
        sessionPercent: Double?, sessionResetsAt: TimeInterval?,
        weekPercent: Double?, weekResetsAt: TimeInterval?, configDir: URL
    ) {
        guard sessionPercent != nil || weekPercent != nil else { return }

        func field(_ d: Double?) -> String { d.map { String($0) } ?? "" }
        let line =
            "\(field(sessionPercent))|\(field(sessionResetsAt))|\(field(weekPercent))"
            + "|\(field(weekResetsAt))|\(Int(Date().timeIntervalSince1970))\n"
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path, isDirectory: &isDir), !isDir.boolValue {
            try? fm.removeItem(at: directory)  // the old single-file format, single-account only
        }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? line.write(
            to: directory.appendingPathComponent(accountKey(for: configDir)), atomically: true,
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
        // A bare agent default (~/.claude, ~/.codex) first, then
        // alphabetically by key, so the row does not reshuffle from tick to
        // tick even if two accounts share a shortened display label.
        func sortKey(_ account: String) -> String { isDefaultKey(account) ? "" : account }
        return snapshots.sorted { sortKey($0.account) < sortKey($1.account) }
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
