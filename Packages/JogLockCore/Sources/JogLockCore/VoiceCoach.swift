//
//  VoiceCoach.swift
//  JogLockCore
//
//  What the voice coach says and when: a line every 500 m, at halfway, near
//  the end and at the unlock, plus "nice try" when the step check rejects
//  distance. The app turns the text into speech.
//

import Foundation

public enum NiceTryKind: String, Codable, Sendable {
    case vehicle    // car or bike
    case noSteps    // GPS distance the steps can't explain
}

public enum VoiceCue: Equatable, Sendable {
    case progress(meters: Double)
    case halfway
    case almostThere
    case unlocked
    case bonus(meters: Double)
    case niceTry(NiceTryKind)
}

/// Decides which cue, if any, to speak as the live distance grows. At most
/// one cue per update, so the coach never talks over itself.
public struct VoiceCoachPlanner: Sendable {
    public let interval: Double
    public let almostThereMeters: Double
    private var milestonesSaid = 0
    private var saidHalfway = false
    private var saidAlmostThere = false
    private var saidUnlocked = false

    public init(interval: Double = 500, almostThereMeters: Double = 100) {
        self.interval = interval
        self.almostThereMeters = almostThereMeters
    }

    public mutating func cue(meters: Double, target: Double, unlocked: Bool) -> VoiceCue? {
        let milestones = interval > 0 ? Int((meters / interval).rounded(.down)) : 0
        let newMilestone = milestones > milestonesSaid
        if newMilestone {
            milestonesSaid = milestones
        }
        if unlocked {
            if !saidUnlocked {
                saidUnlocked = true
                saidHalfway = true
                saidAlmostThere = true
                return .unlocked
            }
            return newMilestone ? .bonus(meters: Double(milestones) * interval) : nil
        }
        guard target > 0 else {
            return newMilestone ? .progress(meters: Double(milestones) * interval) : nil
        }
        if !saidAlmostThere && target >= 3 * almostThereMeters && target - meters <= almostThereMeters && meters < target {
            saidAlmostThere = true
            saidHalfway = true
            return .almostThere
        }
        if !saidHalfway && meters >= target / 2 {
            saidHalfway = true
            return .halfway
        }
        return newMilestone ? .progress(meters: Double(milestones) * interval) : nil
    }
}

public enum VoiceLines {
    /// The default name for the app the runner is running for.
    public static let defaultApp = "Your feed"

    /// A spoken distance: "1.8 kilometres", "750 metres".
    public static func spoken(meters: Double) -> String {
        let m = max(meters, 0)
        if m >= 950 {
            let km = (m / 100).rounded() / 10
            if km == km.rounded() {
                let whole = Int(km)
                return whole == 1 ? "1 kilometre" : "\(whole) kilometres"
            }
            return String(format: "%.1f kilometres", km)
        }
        let rounded = Int((m / 50).rounded()) * 50
        return "\(max(rounded, 50)) metres"
    }

    /// The line for a cue. `variant` picks between versions so the coach doesn't repeat itself.
    public static func text(for cue: VoiceCue, app: String, remainingMeters: Double, variant: Int) -> String {
        let name = app.isEmpty ? defaultApp : app
        let left = spoken(meters: remainingMeters)
        let options: [String]
        switch cue {
        case .progress:
            options = [
                "\(name) is getting closer. \(left) to go.",
                "Another half K. \(name) can sense you coming. \(left) left.",
                "Your thumbs are jealous of your legs. \(left) to go.",
                "\(left) until \(name). The algorithm misses you.",
                "Somewhere, someone is doomscrolling. Not you. \(left) to go.",
                "Half a kilometre closer to \(name). Your future self says thanks.",
            ]
        case .halfway:
            options = [
                "Halfway there. \(name) is putting its shoes on.",
                "Halfway! \(name) just looked up from its phone.",
            ]
        case .almostThere:
            options = [
                "\(left). \(name) is warming up the feed.",
                "Nearly there. Don't let \(name) see you walking.",
            ]
        case .unlocked:
            options = [
                "Unlocked! \(name) is all yours. Try not to undo all that running.",
                "Done! \(name) is open. You earned this scroll.",
            ]
        case .bonus:
            options = [
                "Bonus distance. Show-off.",
                "Still going? Your legs have officially beaten \(name).",
            ]
        case .niceTry(.vehicle):
            options = [
                "Nice try. Cars don't count.",
                "Nice try. Wheels don't count, legs do.",
            ]
        case .niceTry(.noSteps):
            options = [
                "Nice try. Those metres didn't come with steps.",
                "Nice try. No steps, no scroll.",
            ]
        }
        let index = ((variant % options.count) + options.count) % options.count
        return options[index]
    }
}

/// Spots when the step check has just thrown out a meaningful amount of
/// distance, so the app can show a "nice try" card.
public struct NiceTryEvent: Equatable, Sendable {
    public var kind: NiceTryKind
    public var meters: Double

    public init(kind: NiceTryKind, meters: Double) {
        self.kind = kind
        self.meters = meters
    }
}

public struct NiceTryDetector: Sendable {
    public let minimumMeters: Double
    public let cooldown: TimeInterval
    private var reportedVehicle = 0.0
    private var reportedNoSteps = 0.0
    private var lastEvent: TimeInterval?

    public init(minimumMeters: Double = 100, cooldown: TimeInterval = 120) {
        self.minimumMeters = minimumMeters
        self.cooldown = cooldown
    }

    public mutating func check(_ totals: GateTotals, at t: TimeInterval) -> NiceTryEvent? {
        if let last = lastEvent, t - last < cooldown {
            return nil
        }
        let vehicle = totals.vehicleMeters - reportedVehicle
        let noSteps = totals.noStepsMeters - reportedNoSteps
        if vehicle >= minimumMeters && vehicle >= noSteps {
            reportedVehicle = totals.vehicleMeters
            lastEvent = t
            return NiceTryEvent(kind: .vehicle, meters: vehicle)
        }
        if noSteps >= minimumMeters {
            reportedNoSteps = totals.noStepsMeters
            lastEvent = t
            return NiceTryEvent(kind: .noSteps, meters: noSteps)
        }
        return nil
    }
}

// MARK: - 5K plan intervals

extension VoiceLines {
    /// What the coach says as a 5K plan run moves to its next phase.
    public static func interval(_ cue: IntervalCoach.Cue, app: String, variant: Int) -> String {
        let length = FiveKWeek.duration(cue.seconds ?? 60)
        switch cue.phase {
        case .warmUp:
            return "Week \(cue.week) of your 5K plan. Warm up first: walk briskly for \(length)."
        case .run:
            let lines = [
                "Run for \(length). \(app) is waiting at the finish.",
                "Run for \(length). Easy pace: you should still be able to talk.",
                "Run for \(length). Your thumbs are jealous.",
            ]
            return lines[abs(variant) % lines.count]
        case .walk:
            let lines = [
                "Walk for \(length). Catch your breath.",
                "Walk for \(length). Nice work.",
                "Walk for \(length). Shake your arms out.",
            ]
            return lines[abs(variant) % lines.count]
        case .runAllTheWay:
            return "Week \(cue.week). No walking today: run the whole way. Slow is fine."
        }
    }
}
