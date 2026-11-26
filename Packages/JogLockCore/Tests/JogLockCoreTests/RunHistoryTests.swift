import Foundation
import Testing
@testable import JogLockCore

@Suite("The Runs tab: totals, sections, names and splits")
struct RunHistoryTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func run(_ year: Int, _ month: Int, _ day: Int, meters: Double, seconds: Double = 0) -> MonthWrap.Run {
        MonthWrap.Run(start: date(year, month, day), meters: meters, seconds: seconds)
    }

    /// Wednesday 25 November 2026, midday.
    static let now = date(2026, 11, 25, hour: 12)

    @Test("A month: a bar for each day, today marked, other months left out")
    func month() {
        let runs = [Self.run(2026, 11, 3, meters: 3_000, seconds: 1_080), Self.run(2026, 11, 25, meters: 2_000, seconds: 720),
                    Self.run(2026, 10, 31, meters: 5_000), Self.run(2026, 12, 1, meters: 5_000)]
        let totals = PeriodTotals(runs: runs, period: .month, now: Self.now, firstWeekday: 2, calendar: Self.calendar)
        #expect(totals.title == "in November")
        #expect(totals.bars.count == 30)
        #expect(totals.bars[2] == 3_000)
        #expect(totals.bars[24] == 2_000)
        #expect(totals.current == 24)
        #expect(totals.runs == 2)
        #expect(totals.meters == 5_000)
        #expect(totals.pace == 360)
    }

    @Test("A week from the plan's first weekday, also when it runs into the next month")
    func week() {
        let runs = [Self.run(2026, 11, 23, meters: 1_000), Self.run(2026, 11, 25, meters: 2_000),
                    Self.run(2026, 11, 22, meters: 9_000)]
        let totals = PeriodTotals(runs: runs, period: .week, now: Self.now, firstWeekday: 2, calendar: Self.calendar)
        #expect(totals.title == "this week")
        #expect(totals.bars == [1_000, 0, 2_000, 0, 0, 0, 0])
        #expect(totals.current == 2)

        let december = PeriodTotals(runs: [Self.run(2026, 11, 30, meters: 1_500)], period: .week,
                                    now: Self.date(2026, 12, 1), firstWeekday: 2, calendar: Self.calendar)
        #expect(december.bars == [1_500, 0, 0, 0, 0, 0, 0])
        #expect(december.current == 1)
    }

    @Test("A year: a bar for each month")
    func year() {
        let runs = [Self.run(2026, 3, 10, meters: 4_000), Self.run(2026, 11, 3, meters: 3_000), Self.run(2025, 12, 30, meters: 1_000)]
        let totals = PeriodTotals(runs: runs, period: .year, now: Self.now, firstWeekday: 2, calendar: Self.calendar)
        #expect(totals.title == "in 2026")
        #expect(totals.bars.count == 12)
        #expect(totals.bars[2] == 4_000)
        #expect(totals.bars[10] == 3_000)
        #expect(totals.current == 10)
        #expect(totals.runs == 2)
        #expect(totals.meters == 7_000)
    }

    @Test("Sections: this week, last week, earlier this month, then months")
    func sections() {
        let starts = [Self.date(2026, 10, 5), Self.date(2026, 11, 24), Self.date(2025, 12, 3), Self.date(2026, 11, 25),
                      Self.date(2026, 11, 10), Self.date(2026, 11, 20)]
        let sections = RunSection.group(starts, now: Self.now, firstWeekday: 2, calendar: Self.calendar)
        #expect(sections.map(\.title) == ["This week", "Last week", "Earlier in November", "October", "December 2025"])
        #expect(sections.map(\.indices) == [[3, 1], [5], [4], [0], [2]])
    }

    @Test("Run names: Nice try, Treadmill, Long run, or the time of day")
    func names() {
        #expect(Format.runName(hour: 7, mode: nil, meters: 3_000, thrownOut: 300) == "Nice try")
        #expect(Format.runName(hour: 7, mode: .treadmill, meters: 3_000, thrownOut: 0) == "Treadmill")
        #expect(Format.runName(hour: 7, mode: .outdoor, meters: 5_200, thrownOut: 0) == "Long run")
        #expect(Format.runName(hour: 18, mode: nil, meters: 3_000, thrownOut: 100) == "Evening run")
    }

    @Test("Splits from a run's log: each whole kilometre, then the rest")
    func splits() {
        var lines = [LogLine(type: "header", t: 1_000)]
        for minute in 1...20 {
            var fix = LogLine(type: "fix", t: 1_000 + Double(minute) * 60)
            fix.clean = Double(minute) * 180
            lines.append(fix)
        }
        let splits = RunSplits(lines: lines)
        #expect(splits.kilometres.count == 3)
        #expect(splits.kilometres.allSatisfy { abs($0 - 1_000.0 / 3) < 1e-6 })
        #expect(abs(splits.restMeters - 600) < 1e-6)
        #expect(abs(splits.restSeconds - 200) < 1e-6)
        #expect(RunSplits(lines: []).kilometres.isEmpty)
    }
}
