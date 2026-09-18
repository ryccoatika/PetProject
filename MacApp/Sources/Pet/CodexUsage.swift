//  CodexUsage.swift
//  Desktop Pet
//
//  Codex has no equivalent to Claude Code's statusLine — its only external
//  hook (`notify`) carries turn metadata, never usage — so there is nothing
//  for it to push to us. Its rate limits do exist locally, though: Codex
//  writes a `rate_limits` reading into its own session rollout files every
//  so often. This polls those files instead of installing anything into
//  Codex's own config, unlike the Claude side.
//
//  The exact shape (`primary`/`secondary` windows, `used_percent`,
//  `resets_at`) comes from reading Codex's own source
//  (codex-rs/codex-api/src/rate_limits.rs) rather than any documented
//  contract — Codex ships no public spec for its rollout format. A field
//  rename or restructuring in a future Codex release can silently stop this
//  working; the parsing below is deliberately defensive (a bounded search
//  for the distinctive primary+secondary shape, not a fixed exact path) so
//  a minor wrapper change is more likely to survive than break it, but this
//  is unofficial and can break outright on a bigger one.

import Foundation

enum CodexUsage {

    /// Every Codex config folder on this machine: the default ~/.codex plus
    /// any sibling named the way people set up multiple accounts for this
    /// app's Claude side (~/.codex-account1, …). Read-only discovery — nothing
    /// here ever writes to a Codex folder.
    static func homes() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        // dotfiles by design — every Codex home is one — so no
        // .skipsHiddenFiles here.
        guard
            let all = try? FileManager.default.contentsOfDirectory(
                at: home, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        return all.filter { url in
            let name = url.lastPathComponent
            guard name == ".codex" || name.hasPrefix(".codex-") || name.hasPrefix(".codex_")
            else { return false }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                isDir.boolValue
            else { return false }
            // a real Codex home has a sessions folder; a stray dotfile does not
            return FileManager.default.fileExists(
                atPath: url.appendingPathComponent("sessions").path)
        }
    }

    /// Poll every discovered Codex home for its most recent rate-limit
    /// reading and write it into the same store Claude's statusLine feeds.
    /// Cheap to call often: only the single most-recently-modified rollout
    /// file per home is touched, and only its tail is read.
    static func pollAll() {
        for home in homes() {
            guard let (session, week) = latestRateLimits(in: home) else { continue }
            UsageStore.write(
                sessionPercent: session.0, sessionResetsAt: session.1,
                weekPercent: week.0, weekResetsAt: week.1, configDir: home)
        }
    }

    /// The most recent primary (session) and secondary (week) windows found
    /// across this home's rollout files, if any.
    private static func latestRateLimits(
        in home: URL
    ) -> (session: (Double?, TimeInterval?), week: (Double?, TimeInterval?))? {
        guard let file = mostRecentRollout(in: home) else { return nil }
        guard let tail = tailLines(of: file, maxBytes: 512 * 1024) else { return nil }
        // newest event is at the bottom of the file; the first match walking
        // backward is the current reading
        for line in tail.reversed() {
            guard let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            if let windows = findRateLimitWindows(json, depth: 0) {
                return windows
            }
        }
        return nil
    }

    /// The rollout file Codex most recently wrote to, searching the last
    /// two days of date folders (`sessions/YYYY/MM/DD/rollout-*.jsonl`).
    private static func mostRecentRollout(in home: URL) -> URL? {
        let sessions = home.appendingPathComponent("sessions")
        let fm = FileManager.default
        guard
            let candidates = fm.enumerator(
                at: sessions, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
        else { return nil }
        var best: (url: URL, modified: Date)?
        let cutoff = Date().addingTimeInterval(-2 * 86400)
        for case let url as URL in candidates {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                url.pathExtension == "jsonl",
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate,
                modified > cutoff
            else { continue }
            if best == nil || modified > best!.modified { best = (url, modified) }
        }
        return best?.url
    }

    /// The last `maxBytes` of a file, split into lines — enough to find a
    /// recent event without reading a whole (possibly large) transcript.
    private static func tailLines(of file: URL, maxBytes: Int) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.split(separator: "\n").map(String.init)
    }

    /// A bounded-depth search for the distinctive shape of a rate-limit
    /// reading — a dictionary holding both `primary` and `secondary`
    /// windows, each with a `used_percent` — wherever Codex's own event
    /// envelope happens to nest it. Depth is capped well above anything a
    /// rollout event actually needs, as a safety backstop, not a tuned limit.
    private static func findRateLimitWindows(
        _ node: Any, depth: Int
    ) -> (session: (Double?, TimeInterval?), week: (Double?, TimeInterval?))? {
        guard depth < 6 else { return nil }
        if let dict = node as? [String: Any] {
            if let primary = dict["primary"] as? [String: Any],
                let secondary = dict["secondary"] as? [String: Any],
                primary["used_percent"] != nil || secondary["used_percent"] != nil
            {
                func reading(_ w: [String: Any]) -> (Double?, TimeInterval?) {
                    let pct =
                        (w["used_percent"] as? Double)
                        ?? (w["used_percent"] as? Int).map(Double.init)
                    let resets =
                        (w["resets_at"] as? TimeInterval)
                        ?? (w["resets_at"] as? Int).map(TimeInterval.init)
                    return (pct, resets)
                }
                return (reading(primary), reading(secondary))
            }
            for value in dict.values {
                if let found = findRateLimitWindows(value, depth: depth + 1) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findRateLimitWindows(value, depth: depth + 1) { return found }
            }
        }
        return nil
    }
}
