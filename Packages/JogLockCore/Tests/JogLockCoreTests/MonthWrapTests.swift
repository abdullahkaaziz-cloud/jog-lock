import Foundation
import Testing
@testable import JogLockCore

@Suite("Month wrap and the receipt")
struct MonthWrapTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func time(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    typealias Run = MonthWrap.Run

    @Test("A month's distance, runs, longest run, streak, Nice trys and time of day")
    func totals() {
        let runs = [
            Run(start: Self.time(2, 7), meters: 5_000, seconds: 1_800),
            Run(start: Self.time(3, 7, 30), meters: 3_000, seconds: 1_200),
            Run(start: Self.time(4, 18), meters: 6_000, seconds: 2_400),
            Run(start: Self.time(10, 7), meters: 2_000, seconds: 900, thrownOut: 500),
            Run(start: Self.time(20, 9), meters: 0, seconds: 60),
            Run(start: Self.time(31, 10, month: 10), meters: 10_000, seconds: 3_600),
            Run(start: Self.time(1, 0, month: 12), meters: 4_000, seconds: 1_500),
        ]
        let wrap = MonthWrap(runs: runs, month: Self.time(15, 12), calendar: Self.calendar)
        #expect(wrap.title == "November 2026")
        #expect(wrap.runs == 4)
        #expect(wrap.meters == 16_000)
        #expect(wrap.seconds == 6_360)
        #expect(wrap.longest == 6_000)
        #expect(wrap.streak == 3)
        #expect(wrap.niceTries == 1)
        #expect(wrap.timeOfDay == .morning)
        let empty = MonthWrap(runs: [], month: Self.time(15, 12), calendar: Self.calendar)
        #expect(empty.timeOfDay == nil)
        #expect(empty.streak == 0)
    }

    @Test("The distance next to things people know")
    func journeys() {
        #expect(MonthWrap.journey(500) == "Every kilometre counts. Next month's yours.")
        #expect(MonthWrap.journey(5_000) == "That's further than a 5K.")
        #expect(MonthWrap.journey(16_000) == "That's further than a 10K.")
        #expect(MonthWrap.journey(25_000) == "That's further than a half marathon.")
        #expect(MonthWrap.journey(34_000) == "That's further than the English Channel at its narrowest.")
        #expect(MonthWrap.journey(90_000) == "That's a marathon, 2 times over.")
        #expect(MonthWrap.journey(400_000) == "That's the M25 all the way round London, 2 times over.")
    }

    @Test("Running as scrolling paid for, at the rate runs bank minutes")
    func scrolling() {
        let wrap = MonthWrap(runs: [Run(start: Self.time(2, 7), meters: 48_000, seconds: 18_000)],
                             month: Self.time(2, 7), calendar: Self.calendar)
        #expect(wrap.scrolling(minutesPerKm: 15) == "At 15 minutes a km, that's 12 h of scrolling paid for.")
        let short = MonthWrap(runs: [Run(start: Self.time(2, 7), meters: 500, seconds: 300)],
                              month: Self.time(2, 7), calendar: Self.calendar)
        #expect(short.scrolling(minutesPerKm: 15) == nil)
    }

    @Test("Times of day")
    func timesOfDay() {
        #expect(MonthWrap.TimeOfDay(hour: 4) == .morning)
        #expect(MonthWrap.TimeOfDay(hour: 11) == .morning)
        #expect(MonthWrap.TimeOfDay(hour: 12) == .afternoon)
        #expect(MonthWrap.TimeOfDay(hour: 17) == .evening)
        #expect(MonthWrap.TimeOfDay(hour: 21) == .night)
        #expect(MonthWrap.TimeOfDay(hour: 3) == .night)
        #expect(MonthWrap.TimeOfDay.morning.runner == "a morning runner")
        #expect(MonthWrap.TimeOfDay.afternoon.runner == "an afternoon runner")
    }

    @Test("The receipt: what this week's app time would take to run for")
    func owed() {
        let week = ScreenTimeWeek(usage: [.init(key: "a", name: "A", thisWeek: true, seconds: 18_000)],
                                  daysThisWeek: 3)
        #expect(week.owedMeters(minutesPerKm: 15) == 20_000)
        let tiny = ScreenTimeWeek(usage: [.init(key: "a", name: "A", thisWeek: true, seconds: 20)], daysThisWeek: 1)
        #expect(tiny.owedMeters(minutesPerKm: 15) == nil)
    }
}
