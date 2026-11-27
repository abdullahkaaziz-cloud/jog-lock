import Foundation
import Testing
@testable import JogLockCore

@Suite("Lock buddies")
struct BuddiesTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 23 November 2026.
    static func time(day: Int = 0, hour: Int = 9) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    static let today = LockDay(year: 2026, month: 11, day: 23)

    static func ledger(_ rules: LockRules) -> LockLedger {
        var ledger = LockLedger(day: rules.day(of: time(hour: 7), calendar: calendar), rules: rules)
        ledger.resetTarget(rules: rules, at: time(hour: 7))
        return ledger
    }

    static func sam(meters: Double, target: Double = 3_000, met: Bool? = nil, day: LockDay = today) -> BuddyDay {
        BuddyDay(name: "Sam", day: day, meters: meters, target: target, met: met ?? (meters >= target),
                 updated: time(hour: 10))
    }

    @Test("Together: the apps open once you've both run your own target")
    func together() {
        let rules = LockRules(dailyMeters: 2_000, team: .together)
        var ledger = Self.ledger(rules)
        let mine = ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        #expect(!mine)
        #expect(!ledger.isTargetMet)
        #expect(ShieldText.teamLine(ledger, rules: rules) == "You've run yours. Waiting for your buddy.")
        let halfway = ledger.buddyUpdated(Self.sam(meters: 1_200), rules: rules, at: Self.time(hour: 9))
        #expect(!halfway)
        #expect(ShieldText.teamLine(ledger, rules: rules) == "You've run yours. Waiting for Sam: 1.8 km to go.")
        let done = ledger.buddyUpdated(Self.sam(meters: 3_100), rules: rules, at: Self.time(hour: 10))
        #expect(done)
        #expect(ledger.isTargetMet)
        #expect(ledger.bankMinutes == 15)                  // the 1 km past your own target
        #expect(ShieldText.teamLine(ledger, rules: rules) == nil)
    }

    @Test("Together: if your buddy finished first, your run opens the apps")
    func togetherBuddyFirst() {
        let rules = LockRules(dailyMeters: 2_000, team: .together)
        var ledger = Self.ledger(rules)
        _ = ledger.buddyUpdated(Self.sam(meters: 3_000), rules: rules, at: Self.time(hour: 8))
        #expect(!ledger.isTargetMet)
        let opened = ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: Self.time(hour: 9))
        #expect(opened)
    }

    @Test("For each other: your buddy's running opens your apps, not your own")
    func forEachOther() {
        let rules = LockRules(dailyMeters: 2_000, team: .forEachOther)
        var ledger = Self.ledger(rules)
        let own = ledger.credit(run: "a", countedMeters: 5_000, rules: rules, at: Self.time(hour: 8))
        #expect(!own)
        #expect(ledger.remainingMeters(rules: rules) == 2_000)
        #expect(ShieldText.teamLine(ledger, rules: rules) == "Your buddy runs for you today: 2 km to go.")
        _ = ledger.buddyUpdated(Self.sam(meters: 1_500), rules: rules, at: Self.time(hour: 9))
        #expect(ledger.remainingMeters(rules: rules) == 500)
        #expect(ShieldText.teamLine(ledger, rules: rules) == "Sam runs for you today: 500 m to go.")
        let opened = ledger.buddyUpdated(Self.sam(meters: 2_000), rules: rules, at: Self.time(hour: 10))
        #expect(opened)
    }

    @Test("What a buddy shared on another day doesn't count")
    func staleBuddy() {
        let rules = LockRules(dailyMeters: 2_000, team: .forEachOther)
        var ledger = Self.ledger(rules)
        let yesterday = Self.today.adding(days: -1)
        let opened = ledger.buddyUpdated(Self.sam(meters: 9_000, day: yesterday), rules: rules, at: Self.time())
        #expect(!opened)
        #expect(ledger.buddyToday == nil)
    }

    @Test("A rest day is open, team or not")
    func restDay() {
        let rules = LockRules(dailyMeters: 2_000, plan: RunPlan(restDays: [2]), team: .together)    // Mondays off
        let ledger = Self.ledger(rules)
        #expect(ledger.isRestDay)
        #expect(ledger.isTargetMet)
        #expect(ledger.status(name: "Me", at: Self.time()).met)
    }

    @Test("Joining a team never locks apps already open today; leaving one can open them")
    func teamChanges() {
        let alone = LockRules(dailyMeters: 2_000)
        var ledger = Self.ledger(alone)
        _ = ledger.credit(run: "a", countedMeters: 2_000, rules: alone, at: Self.time(hour: 8))
        #expect(ledger.isTargetMet)
        let together = LockRules(dailyMeters: 2_000, team: .together)
        _ = ledger.buddyUpdated(nil, rules: together, at: Self.time(hour: 9))
        #expect(ledger.isTargetMet)

        var waiting = Self.ledger(together)
        _ = waiting.credit(run: "b", countedMeters: 2_500, rules: together, at: Self.time(hour: 8))
        #expect(!waiting.isTargetMet)
        let left = waiting.buddyUpdated(nil, rules: alone, at: Self.time(hour: 9))
        #expect(left)
    }

    @Test("What this phone shares with a buddy")
    func status() {
        let rules = LockRules(dailyMeters: 2_000)
        var ledger = Self.ledger(rules)
        _ = ledger.credit(run: "a", countedMeters: 1_500, rules: rules, at: Self.time(hour: 8))
        let status = ledger.status(name: "Abdullah", at: Self.time(hour: 8))
        #expect(status == BuddyDay(name: "Abdullah", day: Self.today, meters: 1_500, target: 2_000, met: false,
                                   updated: Self.time(hour: 8)))
    }

    @Test("Saved and read back, with the team and the buddy")
    func coding() throws {
        let rules = LockRules(dailyMeters: 2_000, team: .forEachOther)
        var ledger = Self.ledger(rules)
        _ = ledger.buddyUpdated(Self.sam(meters: 500), rules: rules, at: Self.time())
        let again = try JSONDecoder().decode(LockLedger.self, from: JSONEncoder().encode(ledger))
        #expect(again == ledger)
        let rulesAgain = try JSONDecoder().decode(LockRules.self, from: JSONEncoder().encode(rules))
        #expect(rulesAgain.team == .forEachOther)
    }
}
