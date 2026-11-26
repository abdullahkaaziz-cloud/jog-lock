import Foundation
import Testing
@testable import JogLockCore

@Suite("Run plans: rest days, weekly targets and the 5K plan")
struct RunPlanTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 23 November 2026 is a Monday.
    static func time(day: Int = 0, hour: Int = 9) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    static func ledger(_ rules: LockRules) -> LockLedger {
        LockLedger(day: rules.day(of: time(hour: 7), calendar: calendar), rules: rules)
    }

    static func move(_ ledger: inout LockLedger, to day: Int, rules: LockRules) {
        ledger.update(to: time(day: day, hour: 7), rules: rules, calendar: calendar)
    }

    @Test("Days of the week, weeks and day arithmetic")
    func weekdays() {
        let monday = LockDay(year: 2026, month: 11, day: 23)
        let wednesday = LockDay(year: 2026, month: 11, day: 25)
        #expect(monday.weekday == 2)
        #expect(wednesday.weekStart(firstWeekday: 2) == monday)
        #expect(wednesday.weekStart(firstWeekday: 1) == LockDay(year: 2026, month: 11, day: 22))
        #expect(monday.weekStart(firstWeekday: 2) == monday)
        #expect(wednesday.adding(days: 10) == LockDay(year: 2026, month: 12, day: 5))
        #expect(LockDay(year: 2026, month: 12, day: 5).days(since: wednesday) == 10)
        #expect(LockDay(year: 2027, month: 1, day: 1).adding(days: -1) == LockDay(year: 2026, month: 12, day: 31))
    }

    @Test("A rest day is open all day, and what's owed waits for the next run day")
    func restDays() throws {
        let rules = LockRules(dailyMeters: 2_000, plan: RunPlan(restDays: [1]))    // Sundays off
        var ledger = Self.ledger(rules)
        Self.move(&ledger, to: 5, rules: rules)                                     // Saturday
        #expect(!ledger.isRestDay)
        #expect(ledger.targetMeters == 2_000)
        try ledger.borrow(rules: rules)

        Self.move(&ledger, to: 6, rules: rules)                                     // Sunday
        #expect(ledger.isRestDay)
        #expect(ledger.targetMeters == 0)
        #expect(ledger.isTargetMet)
        #expect(ledger.openFor == .day)
        #expect(ledger.owedMeters == 1_000)

        Self.move(&ledger, to: 7, rules: rules)                                     // Monday
        #expect(!ledger.isRestDay)
        #expect(ledger.targetMeters == 3_000)
        #expect(!ledger.isTargetMet)
    }

    @Test("Running on a rest day banks minutes")
    func restDayRun() {
        let rules = LockRules(dailyMeters: 2_000, plan: RunPlan(restDays: [2]))    // Mondays off
        var ledger = Self.ledger(rules)
        ledger.resetTarget(rules: rules, at: Self.time())
        #expect(ledger.isRestDay)
        ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: Self.time(hour: 10))
        #expect(ledger.bankMinutes == 30)
    }

    @Test("A new rest day starts tomorrow, so today can't be made one")
    func restDayWaitsForTomorrow() {
        let daily = LockRules(dailyMeters: 2_000)
        var ledger = Self.ledger(daily)
        let mondaysOff = LockRules(dailyMeters: 2_000, plan: RunPlan(restDays: [2]))
        ledger.update(to: Self.time(hour: 20), rules: mondaysOff, calendar: Self.calendar)
        #expect(ledger.targetMeters == 2_000)
        #expect(!ledger.isTargetMet)
        Self.move(&ledger, to: 7, rules: mondaysOff)
        #expect(ledger.isRestDay)
    }

    @Test("Weekly: distance run ahead counts for the days after; minutes bank past the week")
    func weekly() {
        // 15 km a week, weekends off: 3 km a run day.
        let rules = LockRules(plan: RunPlan(kind: .weekly, restDays: [1, 7], weeklyMeters: 15_000))
        var ledger = Self.ledger(rules)
        ledger.resetTarget(rules: rules, at: Self.time())
        #expect(ledger.targetMeters == 3_000)
        ledger.credit(run: "mon", countedMeters: 6_000, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.isTargetMet)
        #expect(ledger.bankMinutes == 0)

        Self.move(&ledger, to: 1, rules: rules)                                     // Tuesday: covered
        #expect(ledger.targetMeters == 0)
        #expect(ledger.isTargetMet)
        #expect(ledger.weekMeters == 6_000)

        Self.move(&ledger, to: 2, rules: rules)                                     // Wednesday
        #expect(ledger.targetMeters == 3_000)
        ledger.credit(run: "wed", countedMeters: 10_000, rules: rules, at: Self.time(day: 2, hour: 8))
        #expect(ledger.weekMeters == 16_000)
        #expect(ledger.bankMinutes == 15)                                           // 1 km past the week

        Self.move(&ledger, to: 3, rules: rules)                                     // Thursday: week done
        #expect(ledger.targetMeters == 0)
        Self.move(&ledger, to: 5, rules: rules)                                     // Saturday: rest
        #expect(ledger.isRestDay)
        Self.move(&ledger, to: 7, rules: rules)                                     // next Monday: new week
        #expect(ledger.weekMeters == 0)
        #expect(ledger.targetMeters == 3_000)
    }

    @Test("Weekly: a missed day isn't added to the next")
    func weeklyMissedDay() {
        let rules = LockRules(plan: RunPlan(kind: .weekly, restDays: [1, 7], weeklyMeters: 15_000))
        var ledger = Self.ledger(rules)
        Self.move(&ledger, to: 1, rules: rules)
        #expect(ledger.targetMeters == 3_000)
    }

    @Test("The 5K plan: three runs a week, from 1 km to 5 km, then staying at 5 km")
    func fiveK() {
        let start = LockDay(year: 2026, month: 11, day: 23)
        let plan = RunPlan(kind: .fiveK, restDays: RunPlan.fiveKRestDays, fiveKStart: start)
        let rules = LockRules(plan: plan)
        #expect(plan.runDaysPerWeek == 3)
        var ledger = Self.ledger(rules)
        ledger.resetTarget(rules: rules, at: Self.time())
        #expect(ledger.targetMeters == 1_000)                                       // Monday, week 1
        Self.move(&ledger, to: 1, rules: rules)
        #expect(ledger.isRestDay)                                                   // Tuesday
        Self.move(&ledger, to: 2, rules: rules)
        #expect(ledger.targetMeters == 1_000)                                       // Wednesday
        Self.move(&ledger, to: 7, rules: rules)
        #expect(ledger.targetMeters == 1_500)                                       // week 2
        #expect(plan.fiveKWeekNumber(on: start.adding(days: 6)) == 1)
        #expect(plan.fiveKWeekNumber(on: start.adding(days: 56)) == 9)
        #expect(plan.fiveKWeek(on: start.adding(days: 100)).meters == 5_000)
        #expect(plan.fiveKWeekNumber(on: start.adding(days: -3)) == 1)
    }

    @Test("5K plan runs: a warm-up walk, then run and walk intervals")
    func intervals() {
        let first = FiveKWeek.all[0]
        #expect(first.phase(at: 0).phase == .warmUp)
        #expect(first.phase(at: 180).phase == .run)
        #expect(first.phase(at: 239).phase == .run)
        #expect(first.phase(at: 240).phase == .walk)
        #expect(first.phase(at: 240).length == 90)
        #expect(first.phase(at: 330).phase == .run)
        #expect(FiveKWeek.all[8].phase(at: 200).phase == .runAllTheWay)
        #expect(FiveKWeek.all[8].phase(at: 200).length == nil)
        #expect(first.intervalsText == "Run 1 minute, walk 90 seconds")
        #expect(FiveKWeek.all[2].intervalsText == "Run 2 minutes, walk 2 minutes")
        #expect(FiveKWeek.all[8].intervalsText == "Run the whole way")

        var coach = IntervalCoach(week: first)
        #expect(coach.cue(at: 0)?.phase == .warmUp)
        #expect(coach.cue(at: 10) == nil)
        #expect(coach.cue(at: 180) == IntervalCoach.Cue(phase: .run, week: 1, seconds: 60))
        #expect(coach.cue(at: 200) == nil)
        // A late update gives one cue for where the run is now.
        #expect(coach.cue(at: 500) == IntervalCoach.Cue(phase: .run, week: 1, seconds: 60))
    }

    @Test("Never every day off, and only real weekdays")
    func restDayLimits() {
        #expect(RunPlan(restDays: Set(1...7)).validRestDays.isEmpty)
        #expect(RunPlan(restDays: [0, 8, 3]).validRestDays == [3])
        #expect(RunPlan(restDays: Set(1...6)).runDaysPerWeek == 1)
    }

    @Test("A ledger and rules saved before plans existed still read")
    func savedBeforePlans() throws {
        let oldLedger = #"{"day":{"year":2026,"month":11,"day":23},"targetMeters":1000,"owedMeters":0,"#
            + #""borrowedMeters":0,"bankMinutes":0,"runs":{},"spending":false,"bankedMeters":0,"carried":{}}"#
        var ledger = try JSONDecoder().decode(LockLedger.self, from: Data(oldLedger.utf8))
        #expect(!ledger.isRestDay)
        #expect(ledger.weekMeters == 0)
        let oldRules = #"{"dailyMeters":1000,"minutesPerExtraKm":15,"maxBankMinutes":60,"borrowMinutes":30,"#
            + #""borrowMeters":1000,"maxOwedMeters":3000,"borrowBelowMinutes":15,"dayStartHour":4}"#
        let rules = try JSONDecoder().decode(LockRules.self, from: Data(oldRules.utf8))
        #expect(rules.plan == nil)
        ledger.credit(run: "a", countedMeters: 1_500, rules: rules, at: Self.time())
        #expect(ledger.isTargetMet)
        #expect(ledger.bankMinutes == 7.5)
        Self.move(&ledger, to: 1, rules: rules)
        #expect(ledger.weekMeters == 1_500)
        #expect(ledger.targetMeters == 1_000)
    }

    @Test("The 5K plan's phases, numbered: the warm-up, then runs and walks")
    func spans() throws {
        let week3 = FiveKWeek.all[2]                    // run 2 min, walk 2 min
        #expect(week3.spanIndex(at: 179) == 0)
        #expect(week3.spanIndex(at: 180) == 1)
        #expect(week3.spanIndex(at: 300) == 2)
        #expect(week3.span(2) == FiveKWeek.Span(phase: .walk, start: 300, length: 120, number: 1))
        #expect(week3.span(3) == FiveKWeek.Span(phase: .run, start: 420, length: 120, number: 2))
        #expect(week3.span(0).length == 180)

        let week9 = try #require(FiveKWeek.all.last)    // the whole way
        #expect(week9.spanIndex(at: 500) == 1)
        #expect(week9.span(1) == FiveKWeek.Span(phase: .runAllTheWay, start: 180, length: nil, number: 1))
        #expect(week9.span(5) == week9.span(1))
    }

    @Test("Numbered phases agree with the phase at any moment")
    func spansMatchPhases() {
        for week in FiveKWeek.all {
            for elapsed in stride(from: 0.0, through: 3_600, by: 7) {
                let span = week.span(week.spanIndex(at: elapsed))
                let phase = week.phase(at: elapsed)
                #expect(span.phase == phase.phase)
                #expect(span.start == phase.start)
                #expect(span.length == phase.length)
            }
        }
    }
}
