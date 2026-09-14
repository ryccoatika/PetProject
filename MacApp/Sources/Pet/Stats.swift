//  Stats.swift
//  Desktop Pet
//
//  Reading the daily tally that `pet event` keeps, for `pet stats` and the
//  About window.

import Foundation

enum Stats {
    struct Day {
        var sessions = 0
        var tools = 0
        var failures = 0
        var activeSeconds = 0
    }

    struct Totals {
        var days = 0
        var sessions = 0
        var tools = 0
        var failures = 0
    }

    static var file: URL { SkinStore.configDir.appendingPathComponent("stats.json") }

    static func load() -> [String: [String: Any]] {
        (try? Data(contentsOf: file)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]]
        } ?? [:]
    }

    /// Today, plus a roll-up of every day the file still holds.
    static func summary() -> (today: Day, totals: Totals) {
        let all = load()
        var today = Day()
        var totals = Totals()
        for (key, raw) in all {
            let sessions = (raw["sessions"] as? [String])?.count ?? 0
            let tools = raw["tools"] as? Int ?? 0
            let failures = raw["failures"] as? Int ?? 0
            let span = (raw["last"] as? Int ?? 0) - (raw["first"] as? Int ?? 0)
            totals.days += 1
            totals.sessions += sessions
            totals.tools += tools
            totals.failures += failures
            if key == CLI.dayKey() {
                today = Day(
                    sessions: sessions, tools: tools, failures: failures,
                    activeSeconds: max(0, span))
            }
        }
        return (today, totals)
    }

    /// "2h 5m", "12m", "under a minute".
    static func humanSpan(_ seconds: Int) -> String {
        if seconds < 60 { return "under a minute" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// One line for the About window, or nil when nothing has happened today.
    static func aboutLine() -> String? {
        let today = summary().today
        guard today.sessions > 0 || today.tools > 0 else { return nil }
        let s = today.sessions == 1 ? "session" : "sessions"
        return "Today: \(today.sessions) \(s), \(today.tools) tools, "
            + "\(humanSpan(today.activeSeconds)) active."
    }
}
