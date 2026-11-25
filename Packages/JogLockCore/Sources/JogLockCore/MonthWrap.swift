//
//  MonthWrap.swift
//  JogLockCore
//
//  A month of running, wrapped up to share: distance, runs, the longest
//  run and streak, the time of day you run most, the "Nice try"s caught,
//  and the distance put next to things people know. From the runs kept on
//  the phone; nothing else.
//

import Foundation

public struct MonthWrap: Equatable, Sendable {
    /// What a month's wrap needs from a run.
    public struct Run: Equatable, Sendable {
        public var start: Date
        public var meters: Double
        public var seconds: Double
        /// Distance the step check threw out: a car, a bike, or GPS without steps.
        public var thrownOut: Double

        public init(start: Date, meters: Double, seconds: Double, thrownOut: Double = 0) {
            self.start = start
            self.meters = meters
            self.seconds = seconds
            self.thrownOut = thrownOut
        }

        public init(_ summary: RunSummary) {
            self.init(start: summary.startedAt, meters: summary.countedMeters ?? summary.cleanMeters,
                      seconds: summary.movingSeconds,
                      thrownOut: (summary.noStepsMeters ?? 0) + (summary.vehicleMeters ?? 0)
                        + (summary.rejectedMeters ?? 0))
        }
    }

    public enum TimeOfDay: String, CaseIterable, Sendable {
        case morning, afternoon, evening, night

        public init(hour: Int) {
            switch hour {
            case 4..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<21: self = .evening
            default: self = .night
            }
        }

        /// "a morning runner"
        public var runner: String {
            "\(self == .afternoon ? "an" : "a") \(rawValue) runner"
        }
    }

    /// "November 2026".
    public var title: String
    public var runs: Int
    public var meters: Double
    public var seconds: Double
    public var longest: Double
    /// The most days in a row with a run.
    public var streak: Int
    /// Runs where the step check threw out at least `niceTryMeters`.
    public var niceTries: Int
    /// When most runs started; nil without runs.
    public var timeOfDay: TimeOfDay?

    /// Thrown-out distance that counts as a "Nice try".
    public static let niceTryMeters: Double = 200

    /// The wrap for the month containing `date`.
    public init(runs all: [Run], month date: Date, calendar: Calendar = .current) {
        let month = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        let inMonth = all.filter { month.contains($0.start) && $0.start < month.end }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "LLLL yyyy"
        title = formatter.string(from: month.start)
        runs = inMonth.filter { $0.meters > 0 }.count
        meters = inMonth.reduce(0) { $0 + $1.meters }
        seconds = inMonth.reduce(0) { $0 + $1.seconds }
        longest = inMonth.map(\.meters).max() ?? 0
        niceTries = inMonth.filter { $0.thrownOut >= Self.niceTryMeters }.count

        let days = Set(inMonth.filter { $0.meters > 0 }.map { calendar.startOfDay(for: $0.start) }).sorted()
        var best = 0
        var current = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), next == day {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        streak = best

        var counts: [TimeOfDay: Int] = [:]
        for run in inMonth where run.meters > 0 {
            counts[TimeOfDay(hour: calendar.component(.hour, from: run.start)), default: 0] += 1
        }
        timeOfDay = TimeOfDay.allCases.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
            .flatMap { (counts[$0] ?? 0) > 0 ? $0 : nil }
    }

    /// At the rate runs bank minutes: "At 15 minutes a km, that's 12 h 5 min of scrolling paid for."
    public func scrolling(minutesPerKm: Double) -> String? {
        guard meters >= 1_000, minutesPerKm > 0 else { return nil }
        let seconds = Int((meters / 1_000 * minutesPerKm * 60).rounded())
        return "At \(Int(minutesPerKm.rounded())) minutes a km, that's \(ScreenTimeWeek.text(seconds)) of scrolling paid for."
    }

    /// The month's distance next to something people know.
    public var journey: String {
        Self.journey(meters)
    }

    static let landmarks: [(name: String, meters: Double)] = [
        ("a 5K", 5_000),
        ("a 10K", 10_000),
        ("a half marathon", 21_097.5),
        ("the English Channel at its narrowest", 33_300),
        ("a marathon", 42_195),
        ("the M25 all the way round London", 188_000),
    ]

    public static func journey(_ meters: Double) -> String {
        guard let landmark = landmarks.last(where: { $0.meters <= meters }) else {
            return "Every kilometre counts. Next month's yours."
        }
        let times = Int(meters / landmark.meters)
        return times < 2 ? "That's further than \(landmark.name)." : "That's \(landmark.name), \(times) times over."
    }
}
