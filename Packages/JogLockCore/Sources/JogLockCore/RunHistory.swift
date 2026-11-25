//
//  RunHistory.swift
//  JogLockCore
//
//  The Runs tab: totals for this week, month or year with a bar for each
//  day (or month), the list split into This week, Last week and earlier
//  months, each run's name, and a finished run's kilometre splits from its
//  log.
//

import Foundation

/// The stretch of time the Runs tab adds up.
public enum RunPeriod: String, CaseIterable, Sendable {
    case week, month, year
}

/// Distance, runs and time in this week, month or year, with a bar for
/// each day (each month, for a year).
public struct PeriodTotals: Equatable, Sendable {
    public let period: RunPeriod
    /// "this week", "in November", "in 2026".
    public let title: String
    public let runs: Int
    public let meters: Double
    public let seconds: Double
    /// Distance in each bar, oldest first.
    public let bars: [Double]
    /// The bar for today, or this month.
    public let current: Int

    /// Seconds a km, when there's enough distance to tell.
    public var pace: Double? {
        meters >= 50 ? seconds / (meters / 1_000) : nil
    }

    public init(runs all: [MonthWrap.Run], period: RunPeriod, now: Date, firstWeekday: Int,
                calendar base: Calendar = .current) {
        var calendar = base
        calendar.firstWeekday = firstWeekday
        let unit: Calendar.Component
        let barUnit: Calendar.Component
        switch period {
        case .week: (unit, barUnit) = (.weekOfYear, .day)
        case .month: (unit, barUnit) = (.month, .day)
        case .year: (unit, barUnit) = (.year, .month)
        }
        let span = calendar.dateInterval(of: unit, for: now) ?? DateInterval(start: now, duration: 0)
        let inside = all.filter { span.contains($0.start) && $0.start < span.end && $0.meters > 0 }

        // A week that runs into the next month confuses Calendar's day ranges.
        let count = period == .month ? calendar.range(of: .day, in: .month, for: now)?.count ?? 30 : period == .week ? 7 : 12
        var bars = Array(repeating: 0.0, count: count)
        for run in inside {
            let index = calendar.dateComponents([barUnit], from: span.start, to: run.start).value(for: barUnit) ?? 0
            if bars.indices.contains(index) {
                bars[index] += run.meters
            }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        switch period {
        case .week:
            title = "this week"
        case .month:
            formatter.dateFormat = "LLLL"
            title = "in " + formatter.string(from: now)
        case .year:
            formatter.dateFormat = "yyyy"
            title = "in " + formatter.string(from: now)
        }
        self.period = period
        runs = inside.count
        meters = inside.reduce(0) { $0 + $1.meters }
        seconds = inside.reduce(0) { $0 + $1.seconds }
        self.bars = bars
        current = min(count - 1, max(0, calendar.dateComponents([barUnit], from: span.start, to: now).value(for: barUnit) ?? 0))
    }
}

/// A heading in the runs list and the runs under it.
public struct RunSection: Equatable, Sendable {
    public let title: String
    /// Positions in the list given to `RunSection.group`, newest first.
    public let indices: [Int]

    /// Groups runs, newest first, under This week, Last week, Earlier in
    /// November, then each month before ("October", "December 2025").
    public static func group(_ starts: [Date], now: Date, firstWeekday: Int,
                             calendar base: Calendar = .current) -> [RunSection] {
        var calendar = base
        calendar.firstWeekday = firstWeekday
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")

        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let thisYear = calendar.component(.year, from: now)

        func title(_ date: Date) -> String {
            if date >= thisWeek {
                return "This week"
            }
            if date >= lastWeek {
                return "Last week"
            }
            if date >= thisMonth {
                formatter.dateFormat = "LLLL"
                return "Earlier in " + formatter.string(from: date)
            }
            formatter.dateFormat = calendar.component(.year, from: date) == thisYear ? "LLLL" : "LLLL yyyy"
            return formatter.string(from: date)
        }

        var sections: [RunSection] = []
        let order = starts.indices.sorted { starts[$0] > starts[$1] }
        for index in order {
            let heading = title(starts[index])
            if let last = sections.last, last.title == heading {
                sections[sections.count - 1] = RunSection(title: heading, indices: last.indices + [index])
            } else {
                sections.append(RunSection(title: heading, indices: [index]))
            }
        }
        return sections
    }
}

extension Format {
    /// A run's name in the list: "Nice try" when the step check threw out
    /// distance, "Treadmill", "Long run" from 5 km, otherwise by the time
    /// of day it started.
    public static func runName(hour: Int, mode: RunMode?, meters: Double, thrownOut: Double) -> String {
        if thrownOut >= MonthWrap.niceTryMeters {
            return "Nice try"
        }
        if mode == .treadmill {
            return "Treadmill"
        }
        return meters >= 5_000 ? "Long run" : runTitle(hour: hour)
    }
}

/// A finished run's kilometre splits, from the cleaned GPS distance in its
/// log, and the part kilometre at the end.
public struct RunSplits: Equatable, Sendable {
    /// Seconds each whole kilometre took.
    public let kilometres: [Double]
    /// The distance after the last whole kilometre, and how long it took.
    public let restMeters: Double
    public let restSeconds: Double

    public init(lines: [LogLine]) {
        let fixes = lines.filter { $0.type == "fix" && $0.clean != nil }
        let start = lines.first(where: { $0.type == "header" })?.t ?? fixes.first?.t ?? 0
        var splits = KmSplits()
        var meters = 0.0
        var time = 0.0
        for fix in fixes {
            meters = max(meters, fix.clean ?? 0)
            time = fix.t - start
            splits.add(meters: meters, at: time)
        }
        kilometres = splits.seconds
        restMeters = meters - Double(splits.seconds.count) * 1_000
        restSeconds = max(0, time - splits.seconds.reduce(0, +))
    }
}
