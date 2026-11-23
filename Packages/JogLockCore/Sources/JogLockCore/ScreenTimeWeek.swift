//
//  ScreenTimeWeek.swift
//  JogLockCore
//
//  Time on apps, from Screen Time's own minutes: a day on average this week
//  so far against last week, and the apps used most. Worked out inside the
//  Device Activity Report extension, the only place iOS gives the minutes
//  and the apps' names. Nothing here is saved and nothing leaves the
//  extension. From Tilawah Key's ScreenTimeWeek (H5, D94), without its
//  Qur'an and social media split.
//

import Foundation

public struct ScreenTimeWeek: Equatable, Sendable {
    /// An app's or a website's time on one day, as Screen Time gives it.
    public struct Usage: Equatable, Sendable {
        /// The app's bundle identifier or the website's domain; its name when
        /// it has neither.
        public var key: String
        public var name: String
        public var website: Bool
        public var thisWeek: Bool
        public var seconds: TimeInterval

        public init(key: String, name: String, website: Bool = false, thisWeek: Bool, seconds: TimeInterval) {
            self.key = key
            self.name = name
            self.website = website
            self.thisWeek = thisWeek
            self.seconds = seconds
        }
    }

    /// Seconds: in all this week so far and last week, and a day on average.
    public struct Time: Equatable, Sendable {
        public var thisWeek: Int
        public var lastWeek: Int
        public var perDay: Int
        public var lastWeekPerDay: Int

        public init(thisWeek: Int = 0, lastWeek: Int = 0, perDay: Int = 0, lastWeekPerDay: Int = 0) {
            self.thisWeek = thisWeek
            self.lastWeek = lastWeek
            self.perDay = perDay
            self.lastWeekPerDay = lastWeekPerDay
        }
    }

    public struct AppTime: Identifiable, Equatable, Sendable {
        /// `Usage.key`.
        public let id: String
        public let name: String
        public let time: Time

        public init(id: String, name: String, time: Time) {
            self.id = id
            self.name = name
            self.time = time
        }
    }

    /// Everything the report was asked about: the locked apps, or every app.
    public var total = Time()
    /// The apps used most this week, most first, at most `shown`. Websites
    /// count in the total only.
    public var apps: [AppTime] = []
    /// Screen Time recorded something last week, so there's a week to
    /// compare with.
    public var lastWeekRecorded = false

    public static let shown = 5

    /// `daysThisWeek`: this week's days so far, today included (1 to 7).
    /// Last week has 7.
    public init(usage: [Usage], daysThisWeek: Int) {
        let days = Double(max(1, min(7, daysThisWeek)))
        var sum = (now: 0.0, before: 0.0)
        var byApp: [String: (name: String, now: Double, before: Double)] = [:]
        for entry in usage where entry.seconds > 0 {
            if entry.thisWeek {
                sum.now += entry.seconds
            } else {
                sum.before += entry.seconds
                lastWeekRecorded = true
            }
            if !entry.website {
                var app = byApp[entry.key] ?? (entry.name, 0, 0)
                if entry.thisWeek { app.now += entry.seconds } else { app.before += entry.seconds }
                byApp[entry.key] = app
            }
        }
        func time(_ now: Double, _ before: Double) -> Time {
            Time(thisWeek: Int(now.rounded()), lastWeek: Int(before.rounded()),
                 perDay: Int((now / days).rounded()), lastWeekPerDay: Int((before / 7).rounded()))
        }
        total = time(sum.now, sum.before)
        apps = byApp.filter { $0.value.now > 0 }
            .sorted { first, second in
                if first.value.now != second.value.now { return first.value.now > second.value.now }
                if first.value.name != second.value.name { return first.value.name < second.value.name }
                return first.key < second.key
            }
            .prefix(Self.shown)
            .map { AppTime(id: $0.key, name: $0.value.name, time: time($0.value.now, $0.value.before)) }
    }

    public init(total: Time, apps: [AppTime], lastWeekRecorded: Bool) {
        self.total = total
        self.apps = apps
        self.lastWeekRecorded = lastWeekRecorded
    }

    /// Nothing recorded this week yet.
    public var isEmpty: Bool {
        total.thisWeek == 0 && apps.isEmpty
    }

    /// A day on average against last week: "12 min less than last week".
    /// Nil when last week recorded nothing.
    public func change(_ time: Time) -> String? {
        guard lastWeekRecorded else { return nil }
        let now = Self.minutes(time.perDay)
        let before = Self.minutes(time.lastWeekPerDay)
        if now == before { return "Same as last week" }
        if before == 0 { return "None last week" }
        let difference = Self.text(abs(now - before) * 60)
        return now < before ? "\(difference) less than last week" : "\(difference) more than last week"
    }

    /// This week so far, and what it would take to run for it at the rate
    /// runs bank minutes: "This week so far: 5 h 2 min, or 20 km of running
    /// at 15 min a km." Nil under a minute.
    public func running(minutesPerKm: Double) -> String? {
        let minutes = Self.minutes(total.thisWeek)
        guard minutesPerKm > 0, minutes >= 1 else { return nil }
        let meters = Double(minutes) / minutesPerKm * 1_000
        return "This week so far: \(Self.text(total.thisWeek)), or \(Format.shortDistance(meters)) of running "
            + "at \(Int(minutesPerKm.rounded())) min a km."
    }

    // MARK: - Weeks and words

    /// Calendar weeks from the iPhone's first weekday, as Screen Time's
    /// own days are.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.timeZone = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    /// Last week's start to this week's end: the report's days.
    public static func fortnight(of now: Date, calendar: Calendar = ScreenTimeWeek.calendar) -> DateInterval {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        let end = calendar.date(byAdding: .day, value: 7, to: thisWeek) ?? now
        return DateInterval(start: start, end: max(end, start))
    }

    /// This week's start, a week after the report's first day.
    public static func thisWeek(from fortnight: DateInterval, calendar: Calendar = ScreenTimeWeek.calendar) -> Date {
        calendar.date(byAdding: .day, value: 7, to: fortnight.start) ?? fortnight.start
    }

    /// This week's days so far, today included.
    public static func daysThisWeek(since start: Date, now: Date, calendar: Calendar = ScreenTimeWeek.calendar) -> Int {
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        return max(1, min(7, days + 1))
    }

    /// Seconds to whole minutes, to the nearest.
    public static func minutes(_ seconds: Int) -> Int {
        (seconds + 30) / 60
    }

    /// "24 min", "1 h 5 min", "2 h"; "Under 1 min" for a few seconds.
    public static func text(_ seconds: Int) -> String {
        let whole = Self.minutes(seconds)
        if whole == 0 { return seconds > 0 ? "Under 1 min" : "0 min" }
        let hours = whole / 60
        let rest = whole % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// The report at its tallest, to size the card it's drawn in: five
    /// apps, every line at its longest.
    public static let tallest: ScreenTimeWeek = {
        let time = Time(thisWeek: 276_780, lastWeek: 553_560, perDay: 39_540, lastWeekPerDay: 79_080)
        let apps = (1...shown).map { AppTime(id: "\($0)", name: "A long app name", time: time) }
        return ScreenTimeWeek(total: time, apps: apps, lastWeekRecorded: true)
    }()
}
