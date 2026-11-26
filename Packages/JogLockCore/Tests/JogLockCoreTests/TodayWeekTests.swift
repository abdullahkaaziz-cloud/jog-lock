import Foundation
import Testing
@testable import JogLockCore

@Suite("The week on Today: bars, runs so far and the next run day")
struct TodayWeekTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 23 November 2026 is a Monday.
    static let monday = LockDay(year: 2026, month: 11, day: 23)

    static func time(day: Int, hour: Int = 9) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    static func run(day: Int, hour: Int = 9, meters: Double) -> MonthWrap.Run {
        MonthWrap.Run(start: time(day: day, hour: hour), meters: meters, seconds: meters / 3)
    }

    static func week(_ runs: [MonthWrap.Run], today: Int, plan: RunPlan = RunPlan(), daily: Double = 3_000,
                     todayMeters: Double? = nil, todayTarget: Double? = nil) -> TodayWeek {
        TodayWeek(runs: runs, today: monday.adding(days: today), plan: plan, dailyMeters: daily, startHour: 4,
                  todayMeters: todayMeters, todayTarget: todayTarget, calendar: calendar)
    }

    @Test("Seven days from the plan's first weekday, today marked and later days ahead")
    func days() {
        let week = Self.week([], today: 2)
        #expect(week.days.map(\.day) == (0..<7).map { Self.monday.adding(days: $0) })
        #expect(week.days.map(\.isToday) == [false, false, true, false, false, false, false])
        #expect(week.days.map(\.isFuture) == [false, false, false, true, true, true, true])

        let sundayFirst = Self.week([], today: 2, plan: RunPlan(firstWeekday: 1))
        #expect(sundayFirst.days.first?.day == Self.monday.adding(days: -1))
    }

    @Test("Each day's running against its distance, as Monday to Wednesday on the design")
    func fractions() {
        let runs = [Self.run(day: 0, meters: 3_100), Self.run(day: 1, meters: 2_000), Self.run(day: 1, hour: 18, meters: 1_000),
                    Self.run(day: 2, meters: 1_200)]
        let week = Self.week(runs, today: 2)
        #expect(week.days.map(\.fraction) == [1, 1, 0.4, 0, 0, 0, 0])
        #expect(week.runs == 4)
        #expect(week.meters == 7_300)
    }

    @Test("A run before the day's start hour belongs to the day before")
    func dayStart() {
        let week = Self.week([Self.run(day: 2, hour: 2, meters: 3_000)], today: 2)
        #expect(week.days[1].meters == 3_000)
        #expect(week.days[2].meters == 0)
    }

    @Test("Last week's runs, next week's and empty ones don't count")
    func otherWeeks() {
        let runs = [Self.run(day: -1, meters: 5_000), Self.run(day: 7, meters: 5_000), Self.run(day: 0, meters: 0),
                    Self.run(day: 4, meters: 2_000)]
        let week = Self.week(runs, today: 2)
        #expect(week.runs == 0)
        #expect(week.meters == 0)
        #expect(week.days[4].meters == 0)
    }

    @Test("The lock's count of today wins: a run still going, and distance owed")
    func lockToday() {
        let week = Self.week([Self.run(day: 2, meters: 1_200)], today: 2, todayMeters: 1_800, todayTarget: 4_000)
        #expect(week.days[2].meters == 1_800)
        #expect(week.days[2].target == 4_000)
        #expect(week.days[2].fraction == 0.45)
        #expect(week.runs == 1)
    }

    @Test("Rest days have nothing to run, and the next run day skips them")
    func restDays() throws {
        let plan = RunPlan(restDays: [7, 1])                                    // Saturday and Sunday off
        let week = Self.week([Self.run(day: 4, meters: 3_000)], today: 5, plan: plan)
        #expect(week.days.map(\.isRest) == [false, false, false, false, false, true, true])
        #expect(week.days[5].target == 0)
        #expect(week.days[5].fraction == 0)
        let next = try #require(week.next)
        #expect(next.day == Self.monday.adding(days: 7))
        #expect(next.meters == 3_000)
    }

    @Test("A weekly plan: days it has covered show done once run, and next week starts again")
    func weekly() throws {
        let plan = RunPlan(kind: .weekly, restDays: [1], weeklyMeters: 12_000)  // 2 km a day, Sundays off
        let runs = [Self.run(day: 0, meters: 8_000)]
        let week = Self.week(runs, today: 1, plan: plan)
        #expect(week.days[0].fraction == 1)
        #expect(week.days[1].target == 0)                                       // Monday's 8 km covers Tuesday
        let wednesday = try #require(week.next)
        #expect(wednesday.day == Self.monday.adding(days: 2))
        #expect(wednesday.meters == 0)

        let saturday = Self.week(runs, today: 5, plan: plan)
        let monday = try #require(saturday.next)
        #expect(monday.day == Self.monday.adding(days: 7))
        #expect(monday.meters == 2_000)
    }

    @Test("The 5K plan's distance for the week")
    func fiveK() {
        let plan = RunPlan(kind: .fiveK, restDays: RunPlan.fiveKRestDays, fiveKStart: Self.monday)
        let week = Self.week([], today: 0, plan: plan)
        #expect(week.days[0].target == FiveKWeek.all[0].meters)
        #expect(week.next?.day == Self.monday.adding(days: 2))
    }
}
