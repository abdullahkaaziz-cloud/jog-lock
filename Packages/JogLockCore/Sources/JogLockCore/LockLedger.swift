//
//  LockLedger.swift
//  JogLockCore
//
//  The rules of the app lock. Each day the chosen apps stay locked until
//  you've run the day's distance; then they're open until the day ends at
//  4:00, so a late evening isn't cut off at midnight. Distance past the
//  target banks minutes for another day: spent, each minute you actually
//  use the apps takes one off, until they're used up or you lock again.
//  Borrowing adds 30 minutes now and makes tomorrow's run longer.
//
//  iOS can only change the lock at set times through DeviceActivity
//  monitors, so the ledger also keeps the monitor that should be running:
//  one that ends the open day, or one that counts banked minutes as they're
//  used. Each gets a new name, so a callback from an old one is ignored,
//  and the apps open only once iOS has accepted it.
//
//  This follows Tilawah Key's blocking, which went through dozens of iPhone
//  tests. Nothing here touches iOS, so it's tested on Linux.
//

import Foundation

/// A day of the lock, in the runner's time zone. Days start at the rules'
/// hour (4:00), so 2:00 on the 24th still belongs to the 23rd.
public struct LockDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, startHour: Int = 0, calendar: Calendar = .current) {
        var moment = date
        if calendar.component(.hour, from: date) < startHour,
           let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) {
            moment = dayBefore
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: moment)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public static func < (lhs: LockDay, rhs: LockDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// How the lock behaves. The daily distance is the runner's setting; the
/// rest are fixed for now.
public struct LockRules: Codable, Equatable, Sendable {
    /// Distance to run each day before the apps open.
    public var dailyMeters: Double
    /// Minutes banked for each kilometre run past the day's target.
    public var minutesPerExtraKm: Double
    /// The most minutes the bank holds.
    public var maxBankMinutes: Double
    /// Minutes added by borrowing from tomorrow.
    public var borrowMinutes: Double
    /// What borrowing adds to tomorrow's target.
    public var borrowMeters: Double
    /// No more borrowing once this much distance is owed.
    public var maxOwedMeters: Double
    /// Borrowing is for when the bank is nearly empty.
    public var borrowBelowMinutes: Double
    /// The hour a new day starts and the apps lock again.
    public var dayStartHour: Int

    /// iOS monitors no interval under 15 minutes, so a day ending sooner is
    /// monitored this long. The app ends it on time whenever it's open.
    public static let shortestInterval: TimeInterval = 16 * 60
    /// How long a monitor counting banked minutes runs before it's renewed.
    public static let minutesInterval: TimeInterval = 24 * 60 * 60
    /// iOS can say a monitor ended up to this long before its time.
    public static let monitorEndsEarly: TimeInterval = 60

    public init(dailyMeters: Double = 1_000,
                minutesPerExtraKm: Double = 15,
                maxBankMinutes: Double = 60,
                borrowMinutes: Double = 30,
                borrowMeters: Double = 1_000,
                maxOwedMeters: Double = 3_000,
                borrowBelowMinutes: Double = 15,
                dayStartHour: Int = 4) {
        self.dailyMeters = dailyMeters
        self.minutesPerExtraKm = minutesPerExtraKm
        self.maxBankMinutes = maxBankMinutes
        self.borrowMinutes = borrowMinutes
        self.borrowMeters = borrowMeters
        self.maxOwedMeters = maxOwedMeters
        self.borrowBelowMinutes = borrowBelowMinutes
        self.dayStartHour = dayStartHour
    }

    /// The lock day `date` falls in.
    public func day(of date: Date, calendar: Calendar = .current) -> LockDay {
        LockDay(date, startHour: dayStartHour, calendar: calendar)
    }

    /// When the lock day `date` falls in ends: the next time the clock reaches the start hour.
    public func dayEnd(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: dayStartHour, minute: 0, second: 0),
                          matchingPolicy: .nextTime) ?? date.addingTimeInterval(24 * 60 * 60)
    }
}

/// The DeviceActivity monitor that should be running while the apps are open.
public struct LockMonitor: Codable, Equatable, Sendable {
    public enum Purpose: String, Codable, Sendable {
        /// Keeps the apps open until the day ends, then they lock.
        case day
        /// Counts banked minutes as the apps are used.
        case minutes
    }

    /// New for each registration: a callback from any other name is ignored.
    public var name: String
    public var purpose: Purpose
    /// When its interval ends.
    public var end: Date
    /// Minutes: the whole banked minutes when it was registered. Its usage
    /// events, "minute-1" to "minute-\(base)", count down from there.
    public var base: Int
    /// Minutes: the last minute counted.
    public var counted: Int
    /// iOS accepted it. Until then the apps stay shielded.
    public var ready: Bool

    public init(name: String, purpose: Purpose, end: Date, base: Int = 0, counted: Int = 0, ready: Bool = false) {
        self.name = name
        self.purpose = purpose
        self.end = end
        self.base = base
        self.counted = counted
        self.ready = ready
    }

    /// The usage event for the `minute`th minute of use.
    public static func event(_ minute: Int) -> String {
        "minute-\(minute)"
    }

    /// The minute a usage event stands for, if it's one of ours.
    public static func minute(of event: String) -> Int? {
        guard event.hasPrefix("minute-"), let minute = Int(event.dropFirst(7)), minute > 0 else { return nil }
        return minute
    }
}

public enum LockError: Error, Equatable, Sendable {
    /// The apps are open for the rest of the day already.
    case alreadyUnlocked
    /// No whole banked minute to spend.
    case noMinutes
    /// Borrowing waits until the bank is nearly empty.
    case stillHaveMinutes(Int)
    case alreadyBorrowedToday
    case owedLimit(owedMeters: Double)
}

/// One day of the lock, plus what carries over between days: banked minutes,
/// borrowed distance and the monitor that's running.
public struct LockLedger: Codable, Equatable, Sendable {
    public private(set) var day: LockDay
    /// What today's runs have to add up to: the daily distance plus what's
    /// owed. Fixed when the day starts, so a lower setting only counts from
    /// tomorrow.
    public private(set) var targetMeters: Double
    /// Distance borrowed on earlier days and not run yet. Part of today's target.
    public private(set) var owedMeters: Double = 0
    /// Distance borrowed today, added to tomorrow's target.
    public private(set) var borrowedMeters: Double = 0
    public private(set) var bankMinutes: Double = 0
    /// Counted distance of each of today's runs, by run ID.
    public private(set) var runs: [String: Double] = [:]
    /// When today's target was met.
    public private(set) var unlockedAt: Date?
    /// The runner opened the apps on banked minutes.
    public private(set) var spending = false
    /// The monitor iOS should be running.
    public private(set) var monitor: LockMonitor?
    /// Distance past the target already turned into minutes.
    private var bankedMeters: Double = 0
    /// The part of a run credited to the day before (a run past the day's start).
    private var carried: [String: Double] = [:]

    public init(day: LockDay, rules: LockRules) {
        self.day = day
        targetMeters = rules.dailyMeters
    }

    /// Counted distance run today.
    public var ranMeters: Double {
        runs.values.reduce(0, +)
    }

    public var remainingMeters: Double {
        max(0, targetMeters - ranMeters)
    }

    public var isTargetMet: Bool {
        unlockedAt != nil
    }

    /// Banked minutes that can be spent: whole ones.
    public var spendableMinutes: Int {
        Int(max(0, bankMinutes))
    }

    /// What the apps should be open for, if anything.
    public var openFor: LockMonitor.Purpose? {
        if isTargetMet {
            return .day
        }
        if spending && spendableMinutes > 0 {
            return .minutes
        }
        return nil
    }

    /// True when the apps should be open now: they're meant to be, and iOS
    /// has accepted the monitor that will lock them again.
    public var isOpen: Bool {
        guard let purpose = openFor, let monitor else { return false }
        return monitor.purpose == purpose && monitor.ready
    }

    /// Why borrowing isn't possible right now, or nil if it is.
    public func borrowProblem(rules: LockRules) -> LockError? {
        if isTargetMet {
            return .alreadyUnlocked
        }
        if borrowedMeters > 0 {
            return .alreadyBorrowedToday
        }
        if owedMeters + rules.borrowMeters > rules.maxOwedMeters + 1e-9 {
            return .owedLimit(owedMeters: owedMeters)
        }
        if Double(spendableMinutes) >= rules.borrowBelowMinutes {
            return .stillHaveMinutes(spendableMinutes)
        }
        return nil
    }

    // MARK: - Days and runs

    /// Starts a new day once the clock has passed the day's end. True if it did.
    @discardableResult
    public mutating func update(to now: Date, rules: LockRules, calendar: Calendar = .current) -> Bool {
        let today = rules.day(of: now, calendar: calendar)
        guard today > day else { return false }
        startDay(today, rules: rules)
        return true
    }

    /// A new day. What was owed is paid if the last day's target was met;
    /// otherwise it carries over, along with anything borrowed that day.
    private mutating func startDay(_ newDay: LockDay, rules: LockRules) {
        owedMeters = (isTargetMet ? 0 : owedMeters) + borrowedMeters
        borrowedMeters = 0
        day = newDay
        targetMeters = rules.dailyMeters + owedMeters
        var nextCarried: [String: Double] = [:]
        for (id, meters) in runs {
            nextCarried[id] = meters + (carried[id] ?? 0)
        }
        carried = nextCarried
        runs = [:]
        bankedMeters = 0
        unlockedAt = nil
        if monitor?.purpose == .day {
            monitor = nil       // its day is over
        }
    }

    /// Sets today's target from the current setting. For when the lock is
    /// turned on, or the setting changes while it's off.
    public mutating func resetTarget(rules: LockRules, at now: Date) {
        targetMeters = rules.dailyMeters + owedMeters
        if unlockedAt == nil && ranMeters > 0 && ranMeters >= targetMeters {
            unlockedAt = now
            spending = false
        }
    }

    /// Credits a run's counted distance so far. Call it as the run goes and
    /// at the end; a figure no higher than before is ignored. Returns true
    /// when this credit is what met today's target.
    @discardableResult
    public mutating func credit(run id: String, countedMeters: Double, rules: LockRules, at now: Date) -> Bool {
        let today = countedMeters - (carried[id] ?? 0)
        guard today > (runs[id] ?? 0) else { return false }
        runs[id] = today

        var justUnlocked = false
        if unlockedAt == nil && ranMeters >= targetMeters {
            unlockedAt = now
            spending = false    // the whole day is open; minutes left stay banked
            justUnlocked = true
        }
        if unlockedAt != nil {
            let extra = ranMeters - targetMeters
            if extra > bankedMeters {
                let earned = (extra - bankedMeters) / 1_000 * rules.minutesPerExtraKm
                if bankMinutes < rules.maxBankMinutes {
                    bankMinutes = min(rules.maxBankMinutes, bankMinutes + earned)
                }
                bankedMeters = extra
            }
        }
        return justUnlocked
    }

    // MARK: - Banked minutes and borrowing

    /// Opens the apps on banked minutes, until they're used up or the runner
    /// locks again.
    public mutating func startSpending() throws {
        if isTargetMet {
            throw LockError.alreadyUnlocked
        }
        if spendableMinutes < 1 {
            throw LockError.noMinutes
        }
        spending = true
    }

    /// Locks the apps again. The minutes left stay in the bank.
    @discardableResult
    public mutating func stopSpending() -> Bool {
        guard spending else { return false }
        spending = false
        return true
    }

    /// Adds `rules.borrowMinutes` to the bank and opens the apps on them;
    /// tomorrow's target goes up by `rules.borrowMeters`. Once a day, with a
    /// nearly empty bank, and not past the owed limit.
    public mutating func borrow(rules: LockRules) throws {
        if let problem = borrowProblem(rules: rules) {
            throw problem
        }
        borrowedMeters = rules.borrowMeters
        bankMinutes += rules.borrowMinutes
        spending = true
    }

    // MARK: - Monitors

    /// Why the monitor needs registering with iOS (again), or nil when the
    /// right one is running, or none is needed. `listed`: iOS lists the
    /// current monitor's name among its activities.
    public func monitorProblem(at now: Date, listed: Bool) -> String? {
        guard let purpose = openFor else { return nil }
        guard let monitor else { return "none yet" }
        if monitor.purpose != purpose {
            return "\(monitor.purpose.rawValue) monitor, apps open for \(purpose.rawValue)"
        }
        if !monitor.ready {
            return "not ready"
        }
        if !listed {
            return "not listed by iOS"
        }
        if monitor.end <= now {
            return "interval ended"
        }
        if purpose == .minutes && monitor.base - monitor.counted != spendableMinutes {
            return "minutes changed"
        }
        return nil
    }

    /// Plans the monitor the apps need now, as `name`, in place of the
    /// current one (whose name is returned so it can be stopped). Nil when
    /// the apps should be locked: then no monitor is needed.
    public mutating func planMonitor(name: String, at now: Date, rules: LockRules,
                                     calendar: Calendar = .current) -> (monitor: LockMonitor?, replaced: String?) {
        let replaced = monitor?.name
        guard let purpose = openFor else {
            monitor = nil
            return (nil, replaced)
        }
        switch purpose {
        case .day:
            let end = max(rules.dayEnd(after: now, calendar: calendar),
                          now.addingTimeInterval(LockRules.shortestInterval))
            monitor = LockMonitor(name: name, purpose: .day, end: end)
        case .minutes:
            monitor = LockMonitor(name: name, purpose: .minutes,
                                  end: now.addingTimeInterval(LockRules.minutesInterval), base: spendableMinutes)
        }
        return (monitor, replaced)
    }

    /// Forgets the monitor: the apps are locked, or the lock is off. Returns
    /// its name, so it can be stopped.
    @discardableResult
    public mutating func dropMonitor() -> String? {
        defer { monitor = nil }
        return monitor?.name
    }

    /// iOS accepted monitor `name`. False when it isn't the current one any
    /// more: stop it.
    public mutating func monitorStarted(_ name: String) -> Bool {
        guard monitor?.name == name else { return false }
        monitor?.ready = true
        return true
    }

    /// A usage event from monitor `name`: "minute-N" means the apps have been
    /// used N minutes since it started. Each new minute takes one off the
    /// bank, however often the event arrives; at 0 the apps lock. True if it
    /// counted.
    @discardableResult
    public mutating func count(monitor name: String, event: String) -> Bool {
        guard spending, var current = monitor, current.name == name, current.purpose == .minutes,
              let minute = LockMonitor.minute(of: event), minute <= current.base, minute > current.counted
        else { return false }
        bankMinutes = max(0, bankMinutes - Double(minute - current.counted))
        current.counted = minute
        monitor = current
        if spendableMinutes < 1 {
            spending = false
        }
        return true
    }

    /// Whether this event is the one that leaves a single minute before the
    /// apps lock again: the moment for the "1 minute left" notification.
    /// Works whether or not the event has been counted yet.
    public func leavesOneMinute(monitor name: String, event: String) -> Bool {
        guard let current = monitor, current.name == name, current.purpose == .minutes,
              let minute = LockMonitor.minute(of: event), current.base - minute == 1
        else { return false }
        var after = self
        after.count(monitor: name, event: event)
        return after.spending && after.spendableMinutes == 1
    }

    /// Whether this event uses the minutes up, so the apps should lock now.
    public func usesUp(monitor name: String, event: String) -> Bool {
        var after = self
        return after.count(monitor: name, event: event) && after.openFor == nil
    }

    public enum MonitorEnd: Equatable, Sendable {
        /// An old monitor: nothing changes.
        case ignored
        /// The apps lock again.
        case locked
        /// The apps stay open: register a new monitor.
        case renew
    }

    /// Monitor `name`'s interval ended. An open day ends with it (a call up to
    /// a minute early counts as on time); banked minutes left are counted by
    /// a new monitor.
    public mutating func intervalEnded(monitor name: String, at now: Date, rules: LockRules,
                                       calendar: Calendar = .current) -> MonitorEnd {
        guard let current = monitor, current.name == name else { return .ignored }
        if current.purpose == .day && now.addingTimeInterval(LockRules.monitorEndsEarly) >= current.end {
            update(to: max(now, current.end), rules: rules, calendar: calendar)
        }
        guard openFor != nil else {
            monitor = nil
            return .locked
        }
        monitor?.ready = false
        return .renew
    }
}

/// The lock's saved state: on or off, the chosen apps (Screen Time's
/// selection, encoded by the app) and the ledger.
public struct LockState: Codable, Equatable, Sendable {
    public var schema = 1
    public var enabled = false
    public var selection: Data?
    public var rules: LockRules
    public var ledger: LockLedger

    public init(now: Date, rules: LockRules = LockRules(), calendar: Calendar = .current) {
        self.rules = rules
        ledger = LockLedger(day: rules.day(of: now, calendar: calendar), rules: rules)
    }

    /// A saved state this build can trust. Anything else fails closed: the
    /// apps stay as they are and the state isn't overwritten.
    public var valid: Bool {
        schema == 1 && (!enabled || selection != nil) && (0...23).contains(rules.dayStartHour)
            && ledger.bankMinutes >= 0
    }

    /// The apps should be shielded now.
    public var shields: Bool {
        enabled && !ledger.isOpen
    }

    /// What the apps should be open for, with the lock on.
    public var openFor: LockMonitor.Purpose? {
        enabled ? ledger.openFor : nil
    }
}

/// What the shield over a locked app says. Short, as iOS's shield is small:
/// "TikTok is 1.8 km away", a line that changes each minute, and the banked
/// minutes when there are some.
public enum ShieldText {
    public static let button = "Run now"
    public static let close = "Close"

    /// The longest line fits on two lines of the shield.
    public static let lines = [
        "Your thumbs have had enough exercise today.",
        "Your legs miss you. Your feed doesn't.",
        "The algorithm can wait. Your lungs can't.",
        "Every scroll you skip is a stride you take.",
        "It'll still be the same videos when you're back.",
        "Run first. Scroll later. Feel smug forever.",
        "Your trainers are by the door, judging you.",
        "No run, no scroll. Those are the rules.",
        "Somewhere a jogger is having a better time than this.",
        "Fresh air has better graphics.",
        "Strava wants to hear from you.",
        "Five minutes of running beats an hour of this.",
    ]

    /// The line at `date`: the next one each minute. The shield keeps
    /// nothing, so the clock chooses.
    public static func line(at date: Date) -> String {
        let minute = Int((date.timeIntervalSince1970 / 60).rounded(.down))
        return lines[((minute % lines.count) + lines.count) % lines.count]
    }

    /// "TikTok is 1.8 km away".
    public static func title(app: String?, remainingMeters: Double) -> String {
        var name = app.flatMap { $0.isEmpty ? nil : $0 } ?? "This app"
        if name.lowercased().hasPrefix("www."), name.count > 4 {
            name = String(name.dropFirst(4))
        }
        guard remainingMeters > 0 else { return "\(name) is locked" }
        return "\(name) is \(Format.shortDistance(remainingMeters)) away"
    }

    public static func subtitle(_ ledger: LockLedger, at date: Date) -> String {
        let minutes = ledger.spendableMinutes
        guard minutes > 0 else { return line(at: date) }
        let unit = minutes == 1 ? "minute" : "minutes"
        return line(at: date) + "\n\nOr use your \(minutes) banked \(unit) in Jog Lock."
    }
}
