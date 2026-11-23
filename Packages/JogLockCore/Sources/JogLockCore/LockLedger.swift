//
//  LockLedger.swift
//  JogLockCore
//
//  The rules of the app lock. Each day the chosen apps stay locked until
//  you've run the day's distance; then they're open until midnight. Distance
//  past the target banks minutes to spend on a later day, and you can borrow
//  half an hour from tomorrow, which makes tomorrow's run longer.
//
//  The app and its Screen Time extensions apply these rules to iOS; nothing
//  here touches iOS, so it's tested on Linux like the rest of the core.
//

import Foundation

/// A calendar day in the runner's time zone.
public struct LockDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
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
    /// How long a borrowed unlock lasts.
    public var borrowMinutes: Double
    /// What borrowing adds to tomorrow's target.
    public var borrowMeters: Double
    /// No more borrowing once this much distance is owed.
    public var maxOwedMeters: Double

    /// The shortest unlock iOS can time (DeviceActivity's minimum interval).
    public static let minimumSessionMinutes: Double = 15

    public init(dailyMeters: Double = 1_000,
                minutesPerExtraKm: Double = 15,
                maxBankMinutes: Double = 120,
                borrowMinutes: Double = 30,
                borrowMeters: Double = 1_000,
                maxOwedMeters: Double = 3_000) {
        self.dailyMeters = dailyMeters
        self.minutesPerExtraKm = minutesPerExtraKm
        self.maxBankMinutes = maxBankMinutes
        self.borrowMinutes = borrowMinutes
        self.borrowMeters = borrowMeters
        self.maxOwedMeters = maxOwedMeters
    }
}

public enum UnlockSource: String, Codable, Sendable {
    case bank       // paid for with banked minutes
    case borrow     // borrowed from tomorrow
}

/// A timed unlock.
public struct UnlockSession: Codable, Equatable, Sendable {
    public var source: UnlockSource
    public var start: Date
    public var end: Date

    public init(source: UnlockSource, start: Date, end: Date) {
        self.source = source
        self.start = start
        self.end = end
    }

    public var minutes: Double {
        end.timeIntervalSince(start) / 60
    }
}

public enum LockError: Error, Equatable, Sendable {
    /// The apps are already open.
    case alreadyUnlocked
    /// iOS can't time an unlock shorter than 15 minutes.
    case tooShort
    case notEnoughMinutes(available: Double)
    case alreadyBorrowedToday
    case owedLimit(owedMeters: Double)
}

/// One day of the lock, plus what carries over between days: banked
/// minutes and borrowed distance.
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
    public private(set) var session: UnlockSession?
    /// Distance past the target already turned into minutes.
    private var bankedMeters: Double = 0
    /// The part of a run credited to the day before (a run past midnight).
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

    /// The unlock session that's on at `now`, if any.
    public func activeSession(at now: Date) -> UnlockSession? {
        guard let session, session.end > now else { return nil }
        return session
    }

    /// True when the apps should be open.
    public func isUnlocked(at now: Date) -> Bool {
        isTargetMet || activeSession(at: now) != nil
    }

    /// Why borrowing isn't possible right now, or nil if it is.
    public func borrowProblem(rules: LockRules, at now: Date) -> LockError? {
        if isUnlocked(at: now) {
            return .alreadyUnlocked
        }
        if borrowedMeters > 0 {
            return .alreadyBorrowedToday
        }
        if owedMeters + rules.borrowMeters > rules.maxOwedMeters + 1e-9 {
            return .owedLimit(owedMeters: owedMeters)
        }
        return nil
    }

    /// Brings the ledger up to `now`: a new day after midnight, and no session
    /// once its time is up. Returns true if anything changed.
    @discardableResult
    public mutating func update(to now: Date, rules: LockRules, calendar: Calendar = .current) -> Bool {
        var changed = false
        let today = LockDay(now, calendar: calendar)
        if today > day {
            startDay(today, rules: rules)
            changed = true
        }
        if let session, session.end <= now {
            self.session = nil
            changed = true
        }
        return changed
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
    }

    /// Sets today's target from the current setting. For when the lock is
    /// turned on, or the setting changes while it's off.
    public mutating func resetTarget(rules: LockRules, at now: Date) {
        targetMeters = rules.dailyMeters + owedMeters
        if unlockedAt == nil && ranMeters > 0 && ranMeters >= targetMeters {
            unlockedAt = now
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
            session = nil       // the whole day is open now
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

    /// Opens the apps for `minutes` of banked time.
    public mutating func spend(minutes: Double, at now: Date) throws -> UnlockSession {
        if isUnlocked(at: now) {
            throw LockError.alreadyUnlocked
        }
        if minutes < LockRules.minimumSessionMinutes {
            throw LockError.tooShort
        }
        if minutes > bankMinutes + 1e-9 {
            throw LockError.notEnoughMinutes(available: bankMinutes)
        }
        bankMinutes = max(0, bankMinutes - minutes)
        let session = UnlockSession(source: .bank, start: now, end: now.addingTimeInterval(minutes * 60))
        self.session = session
        return session
    }

    /// Opens the apps for `rules.borrowMinutes` now; tomorrow's target goes
    /// up by `rules.borrowMeters`. Once a day, and not past the owed limit.
    public mutating func borrow(rules: LockRules, at now: Date) throws -> UnlockSession {
        if let problem = borrowProblem(rules: rules, at: now) {
            throw problem
        }
        borrowedMeters = rules.borrowMeters
        let session = UnlockSession(source: .borrow, start: now,
                                    end: now.addingTimeInterval(rules.borrowMinutes * 60))
        self.session = session
        return session
    }

    /// Ends the session when its time is up. iOS can report the end a little
    /// early, hence the slack; a newer session that still has time left stays.
    public mutating func endSession(ifDueBy now: Date, slack: TimeInterval = 60) {
        if let session, session.end <= now.addingTimeInterval(slack) {
            self.session = nil
        }
    }

    /// Undoes a session that iOS wouldn't time: the minutes go back in the
    /// bank, or the borrowing is cancelled.
    public mutating func cancel(_ session: UnlockSession) {
        guard self.session == session else { return }
        self.session = nil
        switch session.source {
        case .bank:
            bankMinutes += session.minutes
        case .borrow:
            borrowedMeters = 0
        }
    }
}

/// What the shield over a locked app says.
public enum ShieldText {
    public static let button = "Fine, I'll run"

    /// "TikTok is 1.8 km away".
    public static func title(app: String?, remainingMeters: Double) -> String {
        let name = app.flatMap { $0.isEmpty ? nil : $0 } ?? "This app"
        guard remainingMeters > 0 else { return "\(name) is locked" }
        return "\(name) is \(Format.shortDistance(remainingMeters)) away"
    }

    public static func subtitle(_ ledger: LockLedger) -> String {
        let left = Format.shortDistance(ledger.remainingMeters)
        var parts = [ledger.ranMeters > 0
            ? "Run another \(left) and it's yours for the rest of today."
            : "Run \(left) with Jog Lock and it's yours for the rest of today."]
        if ledger.owedMeters > 0 {
            parts.append("That includes \(Format.shortDistance(ledger.owedMeters)) you borrowed.")
        }
        let minutes = Int(ledger.bankMinutes)
        if Double(minutes) >= LockRules.minimumSessionMinutes {
            parts.append("Or spend some of your \(minutes) banked minutes in Jog Lock.")
        }
        return parts.joined(separator: " ")
    }
}
