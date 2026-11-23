import Foundation
import Testing
@testable import JogLockCore

@Suite("App lock rules")
struct LockLedgerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let rules = LockRules(dailyMeters: 2_000)

    /// A time on 23 November 2026, or `day` days later, in UTC.
    static func time(day: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    func newLedger() -> LockLedger {
        LockLedger(day: LockDay(Self.time(hour: 7), calendar: Self.calendar), rules: rules)
    }

    func nextDay(_ ledger: inout LockLedger, day: Int, hour: Int = 7) {
        ledger.update(to: Self.time(day: day, hour: hour), rules: rules, calendar: Self.calendar)
    }

    @Test("A day starts locked, with the daily distance to run")
    func startsLocked() {
        let ledger = newLedger()
        #expect(!ledger.isUnlocked(at: Self.time(hour: 8)))
        #expect(ledger.targetMeters == 2_000)
        #expect(ledger.remainingMeters == 2_000)
    }

    @Test("Runs add up, and meeting the target opens the apps until midnight")
    func unlockByRunning() {
        var ledger = newLedger()
        // (Mutating calls go in a constant first, then into #expect.)
        let first = ledger.credit(run: "a", countedMeters: 1_200, rules: rules, at: Self.time(hour: 8))
        #expect(first == false)
        #expect(ledger.remainingMeters == 800)
        let second = ledger.credit(run: "b", countedMeters: 900, rules: rules, at: Self.time(hour: 18))
        #expect(second == true)
        #expect(ledger.unlockedAt == Self.time(hour: 18))
        #expect(ledger.isUnlocked(at: Self.time(hour: 23, minute: 59)))
        let again = ledger.credit(run: "b", countedMeters: 1_000, rules: rules, at: Self.time(hour: 18, minute: 5))
        #expect(again == false)

        nextDay(&ledger, day: 1, hour: 0)
        #expect(!ledger.isUnlocked(at: Self.time(day: 1, hour: 0, minute: 1)))
        #expect(ledger.ranMeters == 0)
    }

    @Test("A run's distance counts once, however often it's credited")
    func creditIsIdempotent() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 500, rules: rules, at: Self.time(hour: 8))
        ledger.credit(run: "a", countedMeters: 500, rules: rules, at: Self.time(hour: 8))
        ledger.credit(run: "a", countedMeters: 400, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.ranMeters == 500)
    }

    @Test("Distance past the target banks 15 minutes a kilometre, up to 2 hours")
    func banking() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.bankMinutes == 15)
        ledger.credit(run: "a", countedMeters: 3_500, rules: rules, at: Self.time(hour: 8, minute: 5))
        #expect(ledger.bankMinutes == 22.5)
        ledger.credit(run: "b", countedMeters: 20_000, rules: rules, at: Self.time(hour: 18))
        #expect(ledger.bankMinutes == 120)

        nextDay(&ledger, day: 1)
        #expect(ledger.bankMinutes == 120)
    }

    @Test("Banked minutes buy an unlock of at least 15 minutes on a locked day")
    func spending() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 4_000, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.bankMinutes == 30)
        #expect(throws: LockError.alreadyUnlocked) {
            try ledger.spend(minutes: 15, at: Self.time(hour: 9))
        }

        let morning = Self.time(day: 1, hour: 7)
        nextDay(&ledger, day: 1)
        #expect(throws: LockError.tooShort) {
            try ledger.spend(minutes: 10, at: morning)
        }
        #expect(throws: LockError.notEnoughMinutes(available: 30)) {
            try ledger.spend(minutes: 45, at: morning)
        }
        let session = try ledger.spend(minutes: 15, at: morning)
        #expect(session.source == .bank)
        #expect(session.end == morning.addingTimeInterval(15 * 60))
        #expect(ledger.bankMinutes == 15)
        #expect(ledger.isUnlocked(at: morning.addingTimeInterval(14 * 60)))
        #expect(!ledger.isUnlocked(at: morning.addingTimeInterval(15 * 60)))
        let ended = ledger.update(to: morning.addingTimeInterval(15 * 60), rules: rules, calendar: Self.calendar)
        #expect(ended == true)
        #expect(ledger.session == nil)
    }

    @Test("Borrowing opens the apps for 30 minutes and adds 1 km to tomorrow's run")
    func borrowing() throws {
        var ledger = newLedger()
        let evening = Self.time(hour: 21)
        let session = try ledger.borrow(rules: rules, at: evening)
        #expect(session.source == .borrow)
        #expect(session.end == evening.addingTimeInterval(30 * 60))
        #expect(ledger.isUnlocked(at: evening.addingTimeInterval(60)))
        #expect(ledger.targetMeters == 2_000)
        #expect(throws: LockError.alreadyBorrowedToday) {
            try ledger.borrow(rules: rules, at: evening.addingTimeInterval(45 * 60))
        }

        nextDay(&ledger, day: 1)
        #expect(ledger.owedMeters == 1_000)
        #expect(ledger.targetMeters == 3_000)
        #expect(ledger.session == nil)
        let paidBack = ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(day: 1, hour: 8))
        #expect(paidBack == true)

        nextDay(&ledger, day: 2)
        #expect(ledger.owedMeters == 0)
        #expect(ledger.targetMeters == 2_000)
    }

    @Test("Unpaid borrowing carries over, and stops at 3 km owed")
    func owedLimit() throws {
        var ledger = newLedger()
        for day in 0..<3 {
            _ = try ledger.borrow(rules: rules, at: Self.time(day: day, hour: 21))
            nextDay(&ledger, day: day + 1)
        }
        #expect(ledger.owedMeters == 3_000)
        #expect(ledger.targetMeters == 5_000)
        #expect(throws: LockError.owedLimit(owedMeters: 3_000)) {
            try ledger.borrow(rules: rules, at: Self.time(day: 3, hour: 21))
        }
    }

    @Test("A new daily distance starts tomorrow; today's target stays as it was")
    func targetChangeWaitsForTomorrow() {
        var ledger = newLedger()
        let easier = LockRules(dailyMeters: 500)
        let unlocked = ledger.credit(run: "a", countedMeters: 600, rules: easier, at: Self.time(hour: 8))
        #expect(unlocked == false)
        #expect(ledger.remainingMeters == 1_400)
        ledger.update(to: Self.time(day: 1, hour: 7), rules: easier, calendar: Self.calendar)
        #expect(ledger.targetMeters == 500)
    }

    @Test("Turning the lock on counts today's earlier runs against the current target")
    func resetTarget() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 1_500, rules: rules, at: Self.time(hour: 8))
        #expect(!ledger.isTargetMet)
        ledger.resetTarget(rules: LockRules(dailyMeters: 1_000), at: Self.time(hour: 12))
        #expect(ledger.targetMeters == 1_000)
        #expect(ledger.unlockedAt == Self.time(hour: 12))
    }

    @Test("A run past midnight counts once: the rest of it goes to the new day")
    func runPastMidnight() {
        var ledger = newLedger()
        ledger.credit(run: "late", countedMeters: 1_500, rules: rules, at: Self.time(hour: 23, minute: 55))
        ledger.update(to: Self.time(day: 1, hour: 0, minute: 1), rules: rules, calendar: Self.calendar)
        #expect(ledger.ranMeters == 0)
        ledger.credit(run: "late", countedMeters: 2_100, rules: rules, at: Self.time(day: 1, hour: 0, minute: 5))
        #expect(ledger.ranMeters == 600)
    }

    @Test("Meeting the target during a banked unlock opens the rest of the day")
    func targetDuringSession() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        let morning = Self.time(day: 1, hour: 7)
        nextDay(&ledger, day: 1)
        _ = try ledger.spend(minutes: 15, at: morning)
        let unlocked = ledger.credit(run: "b", countedMeters: 2_000, rules: rules, at: morning.addingTimeInterval(10 * 60))
        #expect(unlocked == true)
        #expect(ledger.session == nil)
        #expect(ledger.isUnlocked(at: Self.time(day: 1, hour: 22)))
    }

    @Test("A session ends when iOS says so, even a little early, but a newer one stays")
    func endSession() throws {
        var ledger = newLedger()
        let evening = Self.time(hour: 21)
        let session = try ledger.borrow(rules: rules, at: evening)
        ledger.endSession(ifDueBy: evening.addingTimeInterval(10 * 60))
        #expect(ledger.session == session)
        ledger.endSession(ifDueBy: session.end.addingTimeInterval(-30))
        #expect(ledger.session == nil)
    }

    @Test("A session iOS wouldn't time is refunded")
    func cancelRefunds() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 4_000, rules: rules, at: Self.time(hour: 8))
        let morning = Self.time(day: 1, hour: 7)
        nextDay(&ledger, day: 1)
        let spent = try ledger.spend(minutes: 30, at: morning)
        ledger.cancel(spent)
        #expect(ledger.bankMinutes == 30)
        #expect(!ledger.isUnlocked(at: morning))

        let borrowed = try ledger.borrow(rules: rules, at: morning)
        ledger.cancel(borrowed)
        #expect(ledger.borrowedMeters == 0)
        #expect(ledger.borrowProblem(rules: rules, at: morning) == nil)
    }

    @Test("The ledger survives a round trip through JSON")
    func coding() throws {
        var ledger = newLedger()
        ledger.credit(run: "late", countedMeters: 2_500, rules: rules, at: Self.time(hour: 23))
        nextDay(&ledger, day: 1)
        _ = try ledger.borrow(rules: rules, at: Self.time(day: 1, hour: 7))
        let decoded = try JSONDecoder().decode(LockLedger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
    }

    @Test("Days compare in calendar order")
    func dayOrder() {
        #expect(LockDay(year: 2026, month: 11, day: 30) < LockDay(year: 2026, month: 12, day: 1))
        #expect(LockDay(year: 2026, month: 12, day: 31) < LockDay(year: 2027, month: 1, day: 1))
        #expect(LockDay(Self.time(hour: 23, minute: 59), calendar: Self.calendar) == LockDay(year: 2026, month: 11, day: 23))
        #expect(LockDay(year: 2026, month: 1, day: 5).description == "2026-01-05")
    }

    @Test("The shield says how far away the app is")
    func shieldTitle() {
        #expect(ShieldText.title(app: "TikTok", remainingMeters: 1_800) == "TikTok is 1.8 km away")
        #expect(ShieldText.title(app: "TikTok", remainingMeters: 2_000) == "TikTok is 2 km away")
        #expect(ShieldText.title(app: nil, remainingMeters: 750) == "This app is 750 m away")
        #expect(ShieldText.title(app: "", remainingMeters: 750) == "This app is 750 m away")
        #expect(ShieldText.title(app: "TikTok", remainingMeters: 0) == "TikTok is locked")
    }

    @Test("The shield's small print mentions borrowed distance and banked minutes")
    func shieldSubtitle() throws {
        var ledger = newLedger()
        #expect(ShieldText.subtitle(ledger) == "Run 2 km with Jog Lock and it's yours for the rest of today.")

        _ = try ledger.borrow(rules: rules, at: Self.time(hour: 7))
        ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        nextDay(&ledger, day: 1)
        ledger.credit(run: "b", countedMeters: 500, rules: rules, at: Self.time(day: 1, hour: 8))
        #expect(ShieldText.subtitle(ledger) == "Run another 2.5 km and it's yours for the rest of today. "
            + "That includes 1 km you borrowed. Or spend some of your 15 banked minutes in Jog Lock.")
    }
}
