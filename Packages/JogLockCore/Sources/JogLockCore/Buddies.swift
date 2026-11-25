//
//  Buddies.swift
//  JogLockCore
//
//  Lock buddies: two people whose locks depend on each other's running.
//  - Together: both run their own target; the apps open for each of you
//    once you've both done it.
//  - For each other: each runs for the other; your apps open when your
//    buddy has run your target, and your running opens theirs.
//  Each phone shares its day (BuddyDay) through iCloud; the rules here
//  decide what the other's day means for this phone's lock.
//

import Foundation

public enum TeamMode: String, Codable, CaseIterable, Sendable {
    case together
    case forEachOther
}

/// A buddy's running today, as their phone last shared it.
public struct BuddyDay: Codable, Equatable, Sendable {
    public var name: String
    public var day: LockDay
    /// Counted distance today.
    public var meters: Double
    /// Their own target today.
    public var target: Double
    /// Their own target is met, or it's their rest day.
    public var met: Bool
    public var updated: Date

    public init(name: String, day: LockDay, meters: Double, target: Double, met: Bool, updated: Date) {
        self.name = name
        self.day = day
        self.meters = meters
        self.target = target
        self.met = met
        self.updated = updated
    }
}

extension LockLedger {
    /// What this phone tells a buddy about today.
    public func status(name: String, at now: Date) -> BuddyDay {
        BuddyDay(name: name, day: day, meters: ranMeters, target: targetMeters,
                 met: isRestDay || ranMeters >= targetMeters, updated: now)
    }

    /// The distance still to run for the apps to open: yours, or with a
    /// team, what your running or your buddy's still needs.
    public func remainingMeters(rules: LockRules) -> Double {
        switch rules.team {
        case .forEachOther:
            return max(0, targetMeters - (buddyToday?.meters ?? 0))
        case .together, nil:
            return remainingMeters
        }
    }
}

extension ShieldText {
    /// The team's line on the shield: who's still running, and how far.
    public static func teamLine(_ ledger: LockLedger, rules: LockRules) -> String? {
        guard let team = rules.team, !ledger.isTargetMet else { return nil }
        let buddy = ledger.buddyToday
        let name = buddy?.name ?? "your buddy"
        switch team {
        case .together:
            guard ledger.ranMeters >= ledger.targetMeters else { return nil }
            let left = max(0, (buddy?.target ?? 0) - (buddy?.meters ?? 0))
            return left > 0 ? "You've run yours. Waiting for \(name): \(Format.shortDistance(left)) to go."
                : "You've run yours. Waiting for \(name)."
        case .forEachOther:
            let left = ledger.remainingMeters(rules: rules)
            return "\(buddy?.name ?? "Your buddy") runs for you today: \(Format.shortDistance(max(10, left))) to go."
        }
    }

    /// The shield's subtitle, with the team's line first when there's a team.
    public static func subtitle(_ ledger: LockLedger, rules: LockRules, at date: Date) -> String {
        let usual = subtitle(ledger, at: date)
        guard let line = teamLine(ledger, rules: rules) else { return usual }
        return line + "\n\n" + usual
    }
}

extension LockDay {
    /// Reads a day back from its description, "2026-11-24".
    public init?(text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}
