//
//  RunPlan.swift
//  JogLockCore
//
//  How the week's running is set out, and so each day's target:
//  - Daily: the same distance every run day.
//  - Weekly: a week's distance shared over the run days. Running ahead
//    counts for the days after, and once the week's done the rest of it
//    is open. A missed day isn't added to the next.
//  - 5K plan: nine weeks of three runs, from 1 km of run/walk intervals
//    to 5 km all the way, with the voice coach calling the intervals.
//  Rest days are open all day, in every kind.
//

import Foundation

public struct RunPlan: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case daily, weekly, fiveK
    }

    public var kind: Kind
    /// Weekdays off, numbered as Calendar does: 1 Sunday to 7 Saturday.
    public var restDays: Set<Int>
    /// The week's distance, for a weekly plan.
    public var weeklyMeters: Double
    /// The 5K plan's first day.
    public var fiveKStart: LockDay?
    /// The weekday weeks start on, numbered as Calendar does.
    public var firstWeekday: Int

    public init(kind: Kind = .daily, restDays: Set<Int> = [], weeklyMeters: Double = 10_000,
                fiveKStart: LockDay? = nil, firstWeekday: Int = 2) {
        self.kind = kind
        self.restDays = restDays
        self.weeklyMeters = weeklyMeters
        self.fiveKStart = fiveKStart
        self.firstWeekday = firstWeekday
    }

    /// The 5K plan's usual rest days: runs on Monday, Wednesday and Saturday.
    public static let fiveKRestDays: Set<Int> = [1, 3, 5, 6]
    /// At least one day a week is a run day.
    public static let mostRestDays = 6

    /// Rest days that count: weekday numbers only, and never the whole week.
    public var validRestDays: Set<Int> {
        let days = restDays.filter { (1...7).contains($0) }
        return days.count > Self.mostRestDays ? [] : days
    }

    public var runDaysPerWeek: Int {
        7 - validRestDays.count
    }

    public func isRestDay(_ day: LockDay) -> Bool {
        validRestDays.contains(day.weekday)
    }

    /// A weekly plan's share for each run day.
    public var weeklyShare: Double {
        weeklyMeters / Double(runDaysPerWeek)
    }

    /// Run days from the start of `day`'s week up to and including `day`.
    public func runDaysSoFar(_ day: LockDay) -> Int {
        let start = day.weekStart(firstWeekday: firstWeekday)
        let count = day.days(since: start) + 1
        return (0..<count).filter { !isRestDay(start.adding(days: $0)) }.count
    }

    /// The 5K plan's week for `day`: 1 to 9, staying at 9 once it's done.
    public func fiveKWeekNumber(on day: LockDay) -> Int {
        guard let start = fiveKStart else { return 1 }
        let days = day.days(since: start)
        return max(1, min(FiveKWeek.all.count, days / 7 + 1))
    }

    public func fiveKWeek(on day: LockDay) -> FiveKWeek {
        FiveKWeek.all[fiveKWeekNumber(on: day) - 1]
    }

    /// The plan's distance for `day`, before anything owed. `weekBefore`:
    /// distance counted this week before `day`.
    public func target(on day: LockDay, dailyMeters: Double, weekBefore: Double) -> Double {
        if isRestDay(day) {
            return 0
        }
        switch kind {
        case .daily:
            return dailyMeters
        case .weekly:
            let due = weeklyShare * Double(runDaysSoFar(day)) - weekBefore
            return min(weeklyShare, max(0, due))
        case .fiveK:
            return fiveKWeek(on: day).meters
        }
    }

    /// Distance today past which runs bank minutes: past the target, and
    /// for a weekly plan past the rest of the week too, so distance isn't
    /// counted twice.
    public func bankAfter(target: Double, owed: Double, on day: LockDay, weekBefore: Double) -> Double {
        guard kind == .weekly, !isRestDay(day) else { return target }
        return max(target, max(0, weeklyMeters - weekBefore) + owed)
    }
}

/// Counted distance in the current week before today.
public struct WeekTally: Codable, Equatable, Sendable {
    public var start: LockDay
    public var meters: Double

    public init(start: LockDay, meters: Double) {
        self.start = start
        self.meters = meters
    }
}

// MARK: - The 5K plan

/// One of the 5K plan's nine weeks: each run's distance, and its intervals
/// after a warm-up walk. Distance and intervals were set for Jog Lock; it
/// isn't an NHS or other branded programme.
public struct FiveKWeek: Equatable, Sendable {
    public let number: Int
    public let meters: Double
    /// Seconds of running in each interval; 0 for running the whole way.
    public let runSeconds: Int
    public let walkSeconds: Int

    public static let warmUpSeconds = 180

    public static let all: [FiveKWeek] = [
        FiveKWeek(number: 1, meters: 1_000, runSeconds: 60, walkSeconds: 90),
        FiveKWeek(number: 2, meters: 1_500, runSeconds: 90, walkSeconds: 120),
        FiveKWeek(number: 3, meters: 2_000, runSeconds: 120, walkSeconds: 120),
        FiveKWeek(number: 4, meters: 2_500, runSeconds: 180, walkSeconds: 120),
        FiveKWeek(number: 5, meters: 3_000, runSeconds: 300, walkSeconds: 120),
        FiveKWeek(number: 6, meters: 3_500, runSeconds: 480, walkSeconds: 120),
        FiveKWeek(number: 7, meters: 4_000, runSeconds: 720, walkSeconds: 120),
        FiveKWeek(number: 8, meters: 4_500, runSeconds: 1_200, walkSeconds: 120),
        FiveKWeek(number: 9, meters: 5_000, runSeconds: 0, walkSeconds: 0),
    ]

    public enum Phase: Equatable, Sendable {
        case warmUp, run, walk, runAllTheWay
    }

    /// The phase `elapsed` seconds into a run, with when it started and how
    /// long it lasts (nil: until the run ends).
    public func phase(at elapsed: TimeInterval) -> (phase: Phase, start: TimeInterval, length: TimeInterval?) {
        let warmUp = TimeInterval(Self.warmUpSeconds)
        if elapsed < warmUp {
            return (.warmUp, 0, warmUp)
        }
        guard runSeconds > 0 else {
            return (.runAllTheWay, warmUp, nil)
        }
        let cycle = TimeInterval(runSeconds + walkSeconds)
        let into = elapsed - warmUp
        let cycleStart = warmUp + (into / cycle).rounded(.down) * cycle
        if elapsed - cycleStart < TimeInterval(runSeconds) {
            return (.run, cycleStart, TimeInterval(runSeconds))
        }
        return (.walk, cycleStart + TimeInterval(runSeconds), TimeInterval(walkSeconds))
    }

    /// "Run 2 min, walk 2 min", or "Run the whole way".
    public var intervalsText: String {
        guard runSeconds > 0 else { return "Run the whole way" }
        return "Run \(Self.duration(runSeconds)), walk \(Self.duration(walkSeconds))"
    }

    /// "90 seconds", "2 minutes", "1 minute".
    public static func duration(_ seconds: Int) -> String {
        if seconds % 60 != 0 || seconds < 60 {
            return "\(seconds) seconds"
        }
        let minutes = seconds / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

/// Says when a 5K plan run moves to its next phase. At most one cue each
/// time it's asked, so a late update doesn't stack them up.
public struct IntervalCoach: Sendable {
    public struct Cue: Equatable, Sendable {
        public let phase: FiveKWeek.Phase
        public let week: Int
        /// Seconds the phase lasts; nil until the run ends.
        public let seconds: Int?
    }

    public let week: FiveKWeek
    private var saidStart: TimeInterval = -1

    public init(week: FiveKWeek) {
        self.week = week
    }

    public mutating func cue(at elapsed: TimeInterval) -> Cue? {
        let now = week.phase(at: max(0, elapsed))
        guard now.start > saidStart else { return nil }
        saidStart = now.start
        return Cue(phase: now.phase, week: week.number, seconds: now.length.map { Int($0) })
    }
}

// MARK: - Days of the week

extension LockDay {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Midday on this day in UTC, for day arithmetic that clocks can't upset.
    private var noon: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    /// 1 Sunday to 7 Saturday.
    public var weekday: Int {
        Self.utc.component(.weekday, from: noon)
    }

    public func adding(days: Int) -> LockDay {
        let date = Self.utc.date(byAdding: .day, value: days, to: noon) ?? noon
        let parts = Self.utc.dateComponents([.year, .month, .day], from: date)
        return LockDay(year: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }

    /// Whole days from `other` to this day (negative before it).
    public func days(since other: LockDay) -> Int {
        Self.utc.dateComponents([.day], from: other.noon, to: noon).day ?? 0
    }

    /// The first day of this day's week.
    public func weekStart(firstWeekday: Int) -> LockDay {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }
}
