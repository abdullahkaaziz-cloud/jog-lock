//
//  TodayWeek.swift
//  JogLockCore
//
//  The week on the Today screen: each day's running against the plan, how
//  many runs so far, and the next day there's something to run. From the
//  runs kept on the phone and the lock's own count of today.
//

import Foundation

/// One day in Today's week bars.
public struct WeekDayProgress: Equatable, Sendable {
    public let day: LockDay
    /// Distance run that day.
    public let meters: Double
    /// The plan's distance that day. 0 on a rest day, and on a day the
    /// weekly plan has already covered.
    public let target: Double
    public let isRest: Bool
    public let isToday: Bool
    public let isFuture: Bool

    /// How much of the day's distance was run, 0 to 1. A day with nothing to
    /// run counts as done once anything was run.
    public var fraction: Double {
        guard target > 0 else { return meters > 0 ? 1 : 0 }
        return min(1, max(0, meters / target))
    }
}

/// Today's week, from the runs on the phone.
public struct TodayWeek: Equatable, Sendable {
    /// The seven days of the week, from the plan's first weekday.
    public let days: [WeekDayProgress]
    /// Runs this week up to today.
    public let runs: Int
    /// Distance this week up to today.
    public let meters: Double
    /// The next day after today that isn't a rest day, and its distance.
    public let next: (day: LockDay, meters: Double)?

    /// - Parameters:
    ///   - runs: finished runs; only this week's are used.
    ///   - todayMeters: today's distance from the lock, when it's on. It
    ///     knows about a run still going and a run that began before the
    ///     day started.
    ///   - todayTarget: today's distance to run from the lock, when it's
    ///     on. It includes distance borrowed earlier.
    public init(runs all: [MonthWrap.Run], today: LockDay, plan: RunPlan, dailyMeters: Double,
                startHour: Int, todayMeters: Double? = nil, todayTarget: Double? = nil,
                calendar: Calendar = .current) {
        let start = today.weekStart(firstWeekday: plan.firstWeekday)
        let thisWeek = all.filter { run in
            let day = LockDay(run.start, startHour: startHour, calendar: calendar)
            return day >= start && day <= today && run.meters > 0
        }
        var byDay: [LockDay: Double] = [:]
        for run in thisWeek {
            byDay[LockDay(run.start, startHour: startHour, calendar: calendar), default: 0] += run.meters
        }
        if let todayMeters {
            byDay[today] = todayMeters
        }

        var days: [WeekDayProgress] = []
        var before = 0.0
        for offset in 0..<7 {
            let day = start.adding(days: offset)
            let meters = day > today ? 0 : byDay[day] ?? 0
            var target = plan.target(on: day, dailyMeters: dailyMeters, weekBefore: before)
            if day == today, let todayTarget {
                target = todayTarget
            }
            days.append(WeekDayProgress(day: day, meters: meters, target: target, isRest: plan.isRestDay(day),
                                        isToday: day == today, isFuture: day > today))
            before += meters
        }
        let weekMeters = days.reduce(0) { $0 + $1.meters }
        self.days = days
        runs = thisWeek.count
        meters = weekMeters

        // The next run day can be in next week, where a weekly plan starts again.
        if let day = (1...7).map({ today.adding(days: $0) }).first(where: { !plan.isRestDay($0) }) {
            let sameWeek = day.weekStart(firstWeekday: plan.firstWeekday) == start
            next = (day: day, meters: plan.target(on: day, dailyMeters: dailyMeters,
                                                  weekBefore: sameWeek ? weekMeters : 0))
        } else {
            next = nil
        }
    }

    public static func == (lhs: TodayWeek, rhs: TodayWeek) -> Bool {
        lhs.days == rhs.days && lhs.runs == rhs.runs && lhs.meters == rhs.meters
            && lhs.next?.day == rhs.next?.day && lhs.next?.meters == rhs.next?.meters
    }
}
