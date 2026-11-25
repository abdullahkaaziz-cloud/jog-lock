//
//  Format.swift
//  JogLockCore
//
//  How distances, times and reasons are shown to the runner.
//

import Foundation

public enum Format {
    public static func km(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// A distance for labels: "1.8 km", "2 km", "750 m".
    public static func shortDistance(_ meters: Double) -> String {
        let m = max(meters, 0)
        if m >= 950 {
            let km = (m / 100).rounded() / 10
            return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
        }
        return "\(max(10, Int((m / 10).rounded()) * 10)) m"
    }

    /// A distance in kilometres to one decimal, without the unit: "1.2".
    public static func tenths(_ meters: Double) -> String {
        String(format: "%.1f", max(meters, 0) / 1_000)
    }

    /// A distance for a big number, with its unit apart: ("1.8", "km"), and
    /// metres under a kilometre: ("650", "m").
    public static func bigDistance(_ meters: Double) -> (value: String, unit: String) {
        let m = max(meters, 0)
        if m >= 995 {
            return (tenths(m), "km")
        }
        return ("\(Int((m / 10).rounded()) * 10)", "m")
    }

    /// When a run started, as people say it: "This morning".
    public static func partOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: "This morning"
        case 12..<17: "This afternoon"
        case 17..<22: "This evening"
        default: "Tonight"
        }
    }

    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public static func reason(_ key: String) -> String {
        switch key {
        case FixDecision.rejectedLowAccuracy.rawValue: return "weak signal"
        case FixDecision.rejectedJump.rawValue: return "jumps"
        case FixDecision.rejectedOutOfOrder.rawValue: return "duplicates"
        case FixDecision.rejectedInvalid.rawValue: return "invalid"
        default: return key
        }
    }

    public static func percent(_ value: Double, versus reference: Double) -> String {
        guard reference > 0 else { return "" }
        let text = String(format: "%+.1f%%", (value - reference) / reference * 100)
        return text == "-0.0%" ? "+0.0%" : text
    }

    /// The Time tile: the clock while a run is going, the finished run's
    /// length after it ends, and 0:00 before the first run.
    public static func elapsed(now: Date, activeSince start: Date?, lastRun: RunSummary?) -> String {
        if let start {
            return duration(now.timeIntervalSince(start))
        }
        if let run = lastRun {
            return duration(run.endedAt.timeIntervalSince(run.startedAt))
        }
        return "0:00"
    }
}
