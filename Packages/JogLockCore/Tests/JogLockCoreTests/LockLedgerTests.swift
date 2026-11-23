import Foundation
import Testing
@testable import JogLockCore

// (Mutating calls go into a constant first, then into #expect.)
@Suite("App lock rules")
struct LockLedgerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2 km a day; the day starts at 4:00.
    let rules = LockRules(dailyMeters: 2_000)

    /// A time on 23 November 2026, or `day` days later, in UTC.
    static func time(day: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: day, to: base)!
    }

    func newLedger() -> LockLedger {
        LockLedger(day: rules.day(of: Self.time(hour: 7), calendar: Self.calendar), rules: rules)
    }

    func nextDay(_ ledger: inout LockLedger, day: Int, hour: Int = 7) {
        ledger.update(to: Self.time(day: day, hour: hour), rules: rules, calendar: Self.calendar)
    }

    /// Plans the monitor the apps need as `name`, and has iOS accept it.
    func openApps(_ ledger: inout LockLedger, name: String, at now: Date) {
        _ = ledger.planMonitor(name: name, at: now, rules: rules, calendar: Self.calendar)
        _ = ledger.monitorStarted(name)
    }

    /// Monitor `name` reports these minutes of use.
    func use(_ ledger: inout LockLedger, name: String, minutes: ClosedRange<Int>) {
        for minute in minutes {
            ledger.count(monitor: name, event: LockMonitor.event(minute))
        }
    }

    // MARK: - Days and runs

    @Test("A day starts locked, with the daily distance to run")
    func startsLocked() {
        let ledger = newLedger()
        #expect(ledger.targetMeters == 2_000)
        #expect(ledger.remainingMeters == 2_000)
        #expect(ledger.openFor == nil)
        #expect(!ledger.isOpen)
    }

    @Test("Days start at 4:00, so a late evening isn't cut off at midnight")
    func dayStartsAtFour() {
        #expect(rules.day(of: Self.time(day: 1, hour: 2), calendar: Self.calendar) == LockDay(year: 2026, month: 11, day: 23))
        #expect(rules.day(of: Self.time(day: 1, hour: 4), calendar: Self.calendar) == LockDay(year: 2026, month: 11, day: 24))
        #expect(rules.dayEnd(after: Self.time(hour: 18), calendar: Self.calendar) == Self.time(day: 1, hour: 4))
        #expect(rules.dayEnd(after: Self.time(day: 1, hour: 3), calendar: Self.calendar) == Self.time(day: 1, hour: 4))
    }

    @Test("Runs add up; meeting the target opens the apps until the day ends at 4:00")
    func unlockByRunning() {
        var ledger = newLedger()
        let first = ledger.credit(run: "a", countedMeters: 1_200, rules: rules, at: Self.time(hour: 8))
        #expect(first == false)
        #expect(ledger.remainingMeters == 800)
        let second = ledger.credit(run: "b", countedMeters: 900, rules: rules, at: Self.time(hour: 18))
        #expect(second == true)
        #expect(ledger.unlockedAt == Self.time(hour: 18))
        #expect(ledger.openFor == .day)
        #expect(!ledger.isOpen)     // shielded until iOS has the monitor that locks again
        let again = ledger.credit(run: "b", countedMeters: 1_000, rules: rules, at: Self.time(hour: 18, minute: 5))
        #expect(again == false)

        openApps(&ledger, name: "d1", at: Self.time(hour: 18))
        #expect(ledger.isOpen)
        #expect(ledger.monitor?.end == Self.time(day: 1, hour: 4))

        nextDay(&ledger, day: 1, hour: 3)
        #expect(ledger.isOpen)      // 3:00 is still yesterday's day
        nextDay(&ledger, day: 1, hour: 4)
        #expect(!ledger.isTargetMet)
        #expect(ledger.monitor == nil)
        #expect(ledger.ranMeters == 0)
        #expect(ledger.openFor == nil)
    }

    @Test("A run's distance counts once, however often it's credited")
    func creditIsIdempotent() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 500, rules: rules, at: Self.time(hour: 8))
        ledger.credit(run: "a", countedMeters: 500, rules: rules, at: Self.time(hour: 8))
        ledger.credit(run: "a", countedMeters: 400, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.ranMeters == 500)
    }

    @Test("A run past the day's start counts once: the rest of it goes to the new day")
    func runPastDayStart() {
        var ledger = newLedger()
        ledger.credit(run: "late", countedMeters: 1_500, rules: rules, at: Self.time(day: 1, hour: 3, minute: 50))
        #expect(ledger.ranMeters == 1_500)
        ledger.update(to: Self.time(day: 1, hour: 4, minute: 1), rules: rules, calendar: Self.calendar)
        #expect(ledger.ranMeters == 0)
        ledger.credit(run: "late", countedMeters: 2_100, rules: rules, at: Self.time(day: 1, hour: 4, minute: 5))
        #expect(ledger.ranMeters == 600)
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

    // MARK: - Banked minutes

    @Test("Distance past the target banks 15 minutes a kilometre, up to an hour")
    func banking() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.bankMinutes == 15)
        ledger.credit(run: "a", countedMeters: 3_500, rules: rules, at: Self.time(hour: 8, minute: 5))
        #expect(ledger.bankMinutes == 22.5)
        ledger.credit(run: "b", countedMeters: 20_000, rules: rules, at: Self.time(hour: 18))
        #expect(ledger.bankMinutes == 60)

        nextDay(&ledger, day: 1)
        #expect(ledger.bankMinutes == 60)
    }

    @Test("Spent minutes are minutes of use, counted once each; at 0 the apps lock")
    func spending() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 4_000, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.bankMinutes == 30)
        #expect(throws: LockError.alreadyUnlocked) {
            try ledger.startSpending()
        }

        nextDay(&ledger, day: 1)
        let morning = Self.time(day: 1, hour: 7)
        try ledger.startSpending()
        #expect(ledger.openFor == .minutes)
        #expect(!ledger.isOpen)
        let planned = ledger.planMonitor(name: "m1", at: morning, rules: rules, calendar: Self.calendar)
        #expect(planned.monitor?.base == 30)
        #expect(planned.monitor?.end == morning.addingTimeInterval(24 * 60 * 60))
        let started = ledger.monitorStarted("m1")
        #expect(started == true)
        #expect(ledger.isOpen)

        let counted = ledger.count(monitor: "m1", event: "minute-1")
        let old = ledger.count(monitor: "m0", event: "minute-2")
        let again = ledger.count(monitor: "m1", event: "minute-1")
        #expect(counted == true)
        #expect(old == false)
        #expect(again == false)
        #expect(ledger.bankMinutes == 29)

        #expect(ledger.leavesOneMinute(monitor: "m1", event: "minute-29"))
        #expect(!ledger.leavesOneMinute(monitor: "m1", event: "minute-28"))
        #expect(ledger.usesUp(monitor: "m1", event: "minute-30"))
        use(&ledger, name: "m1", minutes: 2...29)
        #expect(ledger.bankMinutes == 1)
        #expect(ledger.leavesOneMinute(monitor: "m1", event: "minute-29"))   // counted already: still the one
        use(&ledger, name: "m1", minutes: 30...30)
        #expect(ledger.bankMinutes == 0)
        #expect(!ledger.spending)
        #expect(ledger.openFor == nil)
        #expect(!ledger.isOpen)
    }

    @Test("No whole banked minute, no spending")
    func noMinutes() {
        var ledger = newLedger()
        #expect(throws: LockError.noMinutes) {
            try ledger.startSpending()
        }
    }

    @Test("Locking again keeps the minutes left, and the monitor stops")
    func lockAgainKeepsMinutes() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 4_000, rules: rules, at: Self.time(hour: 8))
        nextDay(&ledger, day: 1)
        let morning = Self.time(day: 1, hour: 7)
        try ledger.startSpending()
        openApps(&ledger, name: "m1", at: morning)
        use(&ledger, name: "m1", minutes: 1...5)
        let stopped = ledger.stopSpending()
        #expect(stopped == true)
        #expect(ledger.bankMinutes == 25)
        #expect(ledger.openFor == nil)
        let plan = ledger.planMonitor(name: "unused", at: morning, rules: rules, calendar: Self.calendar)
        #expect(plan.monitor == nil)
        #expect(plan.replaced == "m1")
        #expect(ledger.monitor == nil)

        try ledger.startSpending()
        openApps(&ledger, name: "m2", at: morning)
        let dropped = ledger.dropMonitor()
        #expect(dropped == "m2")
        #expect(ledger.monitor == nil)
        #expect(!ledger.isOpen)
    }

    @Test("Meeting the target while spending opens the rest of the day; the minutes left stay banked")
    func targetWhileSpending() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        nextDay(&ledger, day: 1)
        let morning = Self.time(day: 1, hour: 7)
        try ledger.startSpending()
        openApps(&ledger, name: "m1", at: morning)
        use(&ledger, name: "m1", minutes: 1...5)
        let unlocked = ledger.credit(run: "b", countedMeters: 2_000, rules: rules,
                                     at: morning.addingTimeInterval(10 * 60))
        #expect(unlocked == true)
        #expect(!ledger.spending)
        #expect(ledger.bankMinutes == 10)
        #expect(ledger.openFor == .day)
        #expect(!ledger.isOpen)
        #expect(ledger.monitorProblem(at: morning, listed: true) == "minutes monitor, apps open for day")
        let plan = ledger.planMonitor(name: "d1", at: morning.addingTimeInterval(10 * 60), rules: rules,
                                      calendar: Self.calendar)
        #expect(plan.replaced == "m1")
        #expect(plan.monitor?.purpose == .day)
        #expect(plan.monitor?.end == Self.time(day: 2, hour: 4))
    }

    // MARK: - Borrowing

    @Test("Borrowing adds 30 minutes now and 1 km to tomorrow's run")
    func borrowing() throws {
        var ledger = newLedger()
        try ledger.borrow(rules: rules)
        #expect(ledger.bankMinutes == 30)
        #expect(ledger.spending)
        #expect(ledger.openFor == .minutes)
        #expect(ledger.targetMeters == 2_000)
        #expect(ledger.borrowProblem(rules: rules) == .alreadyBorrowedToday)

        nextDay(&ledger, day: 1)
        #expect(ledger.owedMeters == 1_000)
        #expect(ledger.targetMeters == 3_000)
        #expect(ledger.bankMinutes == 30)
        let paidBack = ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(day: 1, hour: 8))
        #expect(paidBack == true)

        nextDay(&ledger, day: 2)
        #expect(ledger.owedMeters == 0)
        #expect(ledger.targetMeters == 2_000)
    }

    @Test("Borrowing waits until the bank is nearly empty, and the apps are locked")
    func borrowNeedsEmptyBank() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 4_000, rules: rules, at: Self.time(hour: 8))
        #expect(ledger.borrowProblem(rules: rules) == .alreadyUnlocked)
        nextDay(&ledger, day: 1)
        #expect(ledger.borrowProblem(rules: rules) == .stillHaveMinutes(30))
    }

    @Test("Unpaid borrowing carries over, and stops at 3 km owed")
    func owedLimit() throws {
        var ledger = newLedger()
        for day in 0..<3 {
            try ledger.borrow(rules: rules)
            openApps(&ledger, name: "m\(day)", at: Self.time(day: day, hour: 21))
            use(&ledger, name: "m\(day)", minutes: 1...30)
            nextDay(&ledger, day: day + 1)
        }
        #expect(ledger.owedMeters == 3_000)
        #expect(ledger.targetMeters == 5_000)
        #expect(ledger.borrowProblem(rules: rules) == .owedLimit(owedMeters: 3_000))
        #expect(throws: LockError.owedLimit(owedMeters: 3_000)) {
            try ledger.borrow(rules: rules)
        }
    }

    // MARK: - Monitors

    @Test("A monitor needs registering when there's none, it isn't ready, iOS lost it or its time is up")
    func monitorProblems() {
        var ledger = newLedger()
        let now = Self.time(hour: 18)
        #expect(ledger.monitorProblem(at: now, listed: false) == nil)       // locked: none needed
        ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: now)
        #expect(ledger.monitorProblem(at: now, listed: false) == "none yet")
        _ = ledger.planMonitor(name: "d1", at: now, rules: rules, calendar: Self.calendar)
        #expect(ledger.monitorProblem(at: now, listed: true) == "not ready")
        _ = ledger.monitorStarted("d1")
        #expect(ledger.monitorProblem(at: now, listed: false) == "not listed by iOS")
        #expect(ledger.monitorProblem(at: now, listed: true) == nil)
        #expect(ledger.monitorProblem(at: Self.time(day: 1, hour: 5), listed: true) == "interval ended")
    }

    @Test("Borrowing while spending needs a new monitor for the extra minutes")
    func minutesChanged() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 2_400, rules: rules, at: Self.time(hour: 8))
        nextDay(&ledger, day: 1)
        let morning = Self.time(day: 1, hour: 7)
        #expect(ledger.bankMinutes == 6)
        try ledger.startSpending()
        openApps(&ledger, name: "m1", at: morning)
        #expect(ledger.monitorProblem(at: morning, listed: true) == nil)
        try ledger.borrow(rules: rules)
        #expect(ledger.bankMinutes == 36)
        #expect(ledger.monitorProblem(at: morning, listed: true) == "minutes changed")
    }

    @Test("Only the newest monitor can open the apps")
    func staleMonitorStarted() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: Self.time(hour: 18))
        _ = ledger.planMonitor(name: "d1", at: Self.time(hour: 18), rules: rules, calendar: Self.calendar)
        let plan = ledger.planMonitor(name: "d2", at: Self.time(hour: 18), rules: rules, calendar: Self.calendar)
        #expect(plan.replaced == "d1")
        let stale = ledger.monitorStarted("d1")
        #expect(stale == false)
        #expect(!ledger.isOpen)
        let current = ledger.monitorStarted("d2")
        #expect(current == true)
        #expect(ledger.isOpen)
    }

    @Test("The day's monitor ending locks the apps; up to a minute early counts as on time")
    func dayMonitorEnds() {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: Self.time(hour: 18))
        openApps(&ledger, name: "d1", at: Self.time(hour: 18))
        let end = Self.time(day: 1, hour: 4)
        #expect(ledger.monitor?.end == end)

        let stale = ledger.intervalEnded(monitor: "d0", at: end, rules: rules, calendar: Self.calendar)
        #expect(stale == .ignored)

        var early = ledger
        let tooSoon = early.intervalEnded(monitor: "d1", at: end.addingTimeInterval(-600), rules: rules,
                                          calendar: Self.calendar)
        #expect(tooSoon == .renew)
        #expect(early.isTargetMet)
        #expect(early.monitor?.ready == false)

        let onTime = ledger.intervalEnded(monitor: "d1", at: end.addingTimeInterval(-30), rules: rules,
                                          calendar: Self.calendar)
        #expect(onTime == .locked)
        #expect(!ledger.isTargetMet)
        #expect(ledger.monitor == nil)
        #expect(ledger.day == LockDay(year: 2026, month: 11, day: 24))
    }

    @Test("A day ending in under 15 minutes is monitored for 16, as iOS times nothing shorter")
    func shortDay() {
        var ledger = newLedger()
        let late = Self.time(day: 1, hour: 3, minute: 55)
        ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: late)
        let plan = ledger.planMonitor(name: "d1", at: late, rules: rules, calendar: Self.calendar)
        #expect(plan.monitor?.end == Self.time(day: 1, hour: 4, minute: 11))
    }

    @Test("A minutes monitor ending with minutes left is renewed from what's left")
    func minutesMonitorEnds() throws {
        var ledger = newLedger()
        ledger.credit(run: "a", countedMeters: 4_000, rules: rules, at: Self.time(hour: 8))
        nextDay(&ledger, day: 1)
        let morning = Self.time(day: 1, hour: 7)
        try ledger.startSpending()
        openApps(&ledger, name: "m1", at: morning)
        use(&ledger, name: "m1", minutes: 1...10)
        let later = morning.addingTimeInterval(24 * 60 * 60)
        let renew = ledger.intervalEnded(monitor: "m1", at: later, rules: rules, calendar: Self.calendar)
        #expect(renew == .renew)
        #expect(ledger.monitorProblem(at: later, listed: true) == "not ready")
        let plan = ledger.planMonitor(name: "m2", at: later, rules: rules, calendar: Self.calendar)
        #expect(plan.monitor?.base == 20)
        _ = ledger.monitorStarted("m2")
        use(&ledger, name: "m2", minutes: 1...20)
        #expect(ledger.openFor == nil)
        let done = ledger.intervalEnded(monitor: "m2", at: later, rules: rules, calendar: Self.calendar)
        #expect(done == .locked)
        #expect(ledger.monitor == nil)
    }

    // MARK: - State and words

    @Test("The saved state shields only while the lock is on and the apps aren't open")
    func state() {
        var state = LockState(now: Self.time(hour: 7), rules: rules, calendar: Self.calendar)
        #expect(state.valid)
        #expect(!state.shields)
        state.enabled = true
        #expect(!state.valid)       // on, with no apps chosen
        state.selection = Data([1])
        #expect(state.valid)
        #expect(state.shields)
        #expect(state.openFor == nil)
        state.ledger.credit(run: "a", countedMeters: 2_000, rules: rules, at: Self.time(hour: 18))
        #expect(state.openFor == .day)
        #expect(state.shields)
        _ = state.ledger.planMonitor(name: "d1", at: Self.time(hour: 18), rules: rules, calendar: Self.calendar)
        _ = state.ledger.monitorStarted("d1")
        #expect(!state.shields)
    }

    @Test("The state survives a round trip through JSON")
    func coding() throws {
        var state = LockState(now: Self.time(hour: 7), rules: rules, calendar: Self.calendar)
        state.enabled = true
        state.selection = Data([1, 2, 3])
        state.ledger.credit(run: "late", countedMeters: 2_500, rules: rules, at: Self.time(hour: 23))
        state.ledger.update(to: Self.time(day: 1, hour: 7), rules: rules, calendar: Self.calendar)
        try state.ledger.borrow(rules: rules)
        _ = state.ledger.planMonitor(name: "m1", at: Self.time(day: 1, hour: 7), rules: rules, calendar: Self.calendar)
        let decoded = try JSONDecoder().decode(LockState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    @Test("Days compare in calendar order")
    func dayOrder() {
        #expect(LockDay(year: 2026, month: 11, day: 30) < LockDay(year: 2026, month: 12, day: 1))
        #expect(LockDay(year: 2026, month: 12, day: 31) < LockDay(year: 2027, month: 1, day: 1))
        #expect(LockDay(year: 2026, month: 1, day: 5).description == "2026-01-05")
    }

    @Test("The shield says how far away the app is")
    func shieldTitle() {
        #expect(ShieldText.title(app: "TikTok", remainingMeters: 1_800) == "TikTok is 1.8 km away")
        #expect(ShieldText.title(app: "TikTok", remainingMeters: 2_000) == "TikTok is 2 km away")
        #expect(ShieldText.title(app: "www.reddit.com", remainingMeters: 750) == "reddit.com is 750 m away")
        #expect(ShieldText.title(app: nil, remainingMeters: 750) == "This app is 750 m away")
        #expect(ShieldText.title(app: "", remainingMeters: 750) == "This app is 750 m away")
        #expect(ShieldText.title(app: "TikTok", remainingMeters: 0) == "TikTok is locked")
    }

    @Test("The shield's line changes each minute, with banked minutes beneath when there are some")
    func shieldSubtitle() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(ShieldText.line(at: start) == ShieldText.lines[0])
        #expect(ShieldText.line(at: start.addingTimeInterval(60)) == ShieldText.lines[1])
        #expect(ShieldText.line(at: start.addingTimeInterval(-60)) == ShieldText.lines.last)
        #expect(ShieldText.lines.allSatisfy { $0.count <= 62 })

        var ledger = newLedger()
        #expect(ShieldText.subtitle(ledger, at: start) == ShieldText.lines[0])
        ledger.credit(run: "a", countedMeters: 3_000, rules: rules, at: Self.time(hour: 8))
        #expect(ShieldText.subtitle(ledger, at: start)
            == ShieldText.lines[0] + "\n\nOr use your 15 banked minutes in Jog Lock.")
    }
}
