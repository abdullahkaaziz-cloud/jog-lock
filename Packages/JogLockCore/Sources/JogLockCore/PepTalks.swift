//
//  PepTalks.swift
//  JogLockCore
//
//  Pep talks: a line from an old battle, speech or poem, or a big moment of
//  a fight or war film, spoken in the last 100 m, when the runner slows right
//  down, or when they stop. Each moment has its own switch in Settings.
//
//  The words are either public domain (written before 1929, or history) or
//  Jog Lock's own. Film and TV dialogue is copyrighted, so the film moments
//  are told in new words, without names.
//

import Foundation

/// When a pep talk can come.
public enum PepMoment: String, CaseIterable, Codable, Sendable {
    case lastStretch    // the last 100 m to the run's target
    case slowing        // well below the run's own pace
    case stopped        // standing still
}

/// The moments the runner switched on in Settings.
public struct PepTalkChoices: Equatable, Sendable {
    public var lastStretch: Bool
    public var slowing: Bool
    public var stopped: Bool

    public init(lastStretch: Bool = false, slowing: Bool = false, stopped: Bool = false) {
        self.lastStretch = lastStretch
        self.slowing = slowing
        self.stopped = stopped
    }

    public static let none = PepTalkChoices()
    public static let all = PepTalkChoices(lastStretch: true, slowing: true, stopped: true)
}

public struct PepTalkSettings: Equatable, Sendable {
    public var lastStretchMeters: Double = 100     // m to the target
    public var minimumTarget: Double = 300         // m: on shorter runs it's all last stretch
    public var slowWindow: Double = 30             // s: recent pace is measured over this long
    public var slowRatio: Double = 0.75            // under this share of the run's pace is slowing
    public var recoveredRatio: Double = 0.9        // back over this share, a new slowdown counts
    public var slowAfterSeconds: Double = 180      // s: not in the first minutes
    public var slowAfterMeters: Double = 400       // m: nor in the first stretch
    public var minimumPace: Double = 1.0           // m/s: under this the run's own pace means little
    public var stopSpeed: Double = 0.5             // m/s: slower is stopping, not slowing
    public var latelyWindow: Double = 6            // s: still moving over this long, so not stopping
    public var stopDelay: Double = 15              // s: standing still this long is a stop
    public var stopMeters: Double = 3              // m: under this in stopDelay is standing still
    public var stopAfterMeters: Double = 50        // m: run this far before a stop counts
    public var movedOnMeters: Double = 20          // m: this far past a stop, the next one counts
    public var cooldown: Double = 120              // s: between two slowing or stopping talks

    public init() {}

    public static let standard = PepTalkSettings()
}

/// Decides when to give a pep talk. Feed it the live distance on every update
/// and every few seconds besides, so a stop is noticed while nothing moves.
///
/// - The last stretch is said once, when 100 m or less are left, cooldown or not.
/// - Slowing: the last 30 s ran under 75% of the run's own pace, after the first
///   3 minutes and 400 m. Once per slow patch: speeding back up to 90% counts a
///   new one. Never on a 5K plan run, where walking is part of the plan.
/// - Stopped: under 3 m in 15 s, after the first 50 m. Once per stop.
/// - Slowing and stopping wait 2 minutes after any pep talk, and stop once the
///   target is covered: the job's done.
public struct PepTalkPlanner: Sendable {
    public let settings: PepTalkSettings
    private var samples: [Sample] = []
    private var firstTime: Double?
    private var lastTime = -Double.infinity
    private var saidLastStretch = false
    private var saidSlowing = false
    private var stoppedAt: Double?      // metres where the last stop talk came
    private var lastTalk: Double?

    private struct Sample: Sendable {
        var t: Double
        var meters: Double
    }

    public init(settings: PepTalkSettings = .standard) {
        self.settings = settings
    }

    /// - Parameters:
    ///   - t: seconds on a clock that goes forwards
    ///   - meters: the live distance so far
    ///   - pace: the run's own average moving speed so far, m/s
    ///   - target: the run's target in metres (0 for none)
    ///   - choices: the moments switched on
    ///   - slowingAllowed: false on 5K plan runs
    public mutating func moment(at t: Double, meters: Double, pace: Double, target: Double,
                                choices: PepTalkChoices, slowingAllowed: Bool = true) -> PepMoment? {
        let s = settings
        let now = max(t, lastTime)
        lastTime = now
        if firstTime == nil {
            firstTime = now
        }
        record(now, meters)

        if target >= s.minimumTarget && !saidLastStretch {
            let left = target - meters
            if left <= 0 {
                saidLastStretch = true    // passed it between updates: too late to say
            } else if left <= s.lastStretchMeters {
                saidLastStretch = true
                if choices.lastStretch {
                    lastTalk = now
                    return .lastStretch
                }
            }
        }
        if target > 0 && meters >= target {
            return nil
        }

        let recent = speed(over: s.slowWindow, at: now, meters: meters)
        if let at = stoppedAt, meters - at >= s.movedOnMeters {
            stoppedAt = nil
        }
        if saidSlowing, let recent, recent >= s.recoveredRatio * pace {
            saidSlowing = false
        }
        if let last = lastTalk, now - last < s.cooldown {
            return nil
        }

        if choices.stopped && stoppedAt == nil && meters >= s.stopAfterMeters,
           let still = gained(over: s.stopDelay, at: now, meters: meters), still < s.stopMeters {
            stoppedAt = meters
            lastTalk = now
            return .stopped
        }
        if choices.slowing && slowingAllowed && !saidSlowing,
           let first = firstTime, now - first >= s.slowAfterSeconds, meters >= s.slowAfterMeters,
           pace >= s.minimumPace, let recent, recent >= s.stopSpeed, recent < s.slowRatio * pace,
           let lately = gained(over: s.latelyWindow, at: now, meters: meters),
           lately >= s.stopSpeed * s.latelyWindow {
            saidSlowing = true
            lastTalk = now
            return .slowing
        }
        return nil
    }

    private mutating func record(_ t: Double, _ meters: Double) {
        samples.append(Sample(t: t, meters: meters))
        // Keep one sample older than the longest window, and nothing older than that.
        let keep = max(settings.slowWindow, settings.stopDelay, settings.latelyWindow) * 2
        while samples.count > 1 && samples[1].t <= t - keep {
            samples.removeFirst()
        }
    }

    /// The newest sample at least `seconds` old, unless the gap since is far
    /// longer (the app was asleep): then there's nothing to judge by.
    private func base(_ seconds: Double, at now: Double) -> Sample? {
        guard let base = samples.last(where: { $0.t <= now - seconds }), now - base.t <= seconds * 3 else {
            return nil
        }
        return base
    }

    private func gained(over seconds: Double, at now: Double, meters: Double) -> Double? {
        base(seconds, at: now).map { meters - $0.meters }
    }

    private func speed(over seconds: Double, at now: Double, meters: Double) -> Double? {
        guard let base = base(seconds, at: now), now > base.t else { return nil }
        return (meters - base.meters) / (now - base.t)
    }
}

/// What the coach says. Each line is short enough to hear mid-stride.
public enum PepTalkLines {
    public static func lines(for moment: PepMoment) -> [String] {
        switch moment {
        case .lastStretch:
            return [
                // Rudyard Kipling, "If—" (1910)
                "A hundred metres left. As Kipling put it: fill the unforgiving minute with sixty seconds' worth of distance run.",
                // Julius Caesar crossing the Rubicon, 49 BC
                "The die is cast. Caesar crossed the Rubicon and never looked back. A hundred metres. Don't look back.",
                // Pheidippides, the first marathon (legend; Robert Browning's poem, 1879)
                "The first marathon runner ran all the way to Athens just to shout: rejoice, we conquer! You've only got a hundred metres.",
                // William Shakespeare, Henry V (1599)
                "Stiffen the sinews, summon up the blood! Shakespeare's Henry the Fifth, before his battle. Yours is the last hundred metres.",
                // Jog Lock's own: the last round of a fight film
                "Last round. The bell's about to go and the whole crowd's on its feet. Empty the tank. A hundred metres.",
                // Jog Lock's own: the end of every sports film
                "This is the part of the film where the music kicks in and everyone sprints. A hundred metres. Go!",
            ]
        case .slowing:
            return [
                // William Shakespeare, Henry V (1599)
                "Once more unto the breach, dear friends, once more! Pick the pace back up.",
                // John Paul Jones, 1779, asked to surrender with his ship on fire
                "His ship was on fire when they asked him to surrender. John Paul Jones said: I have not yet begun to fight. Neither have you.",
                // Rudyard Kipling, "If—" (1910)
                "Kipling said: hold on when there is nothing in you, except the will which says: hold on! So hold on.",
                // Alfred Tennyson, "Ulysses" (1842)
                "Though much is taken, much abides. To strive, to seek, to find, and not to yield. Don't yield now.",
                // Jog Lock's own: the corner between rounds
                "Your corner's shouting between rounds: hands up, feet moving, this round is yours. Go and win it.",
                // Jog Lock's own: the half-time talk
                "Half-time talk. Nobody remembers how you started. They remember how you finished. Lift it.",
            ]
        case .stopped:
            return [
                // Bastogne, December 1944: the American general's whole reply to a demand to surrender
                "Surrounded at Bastogne and told to surrender, the general wrote back one word: Nuts! Your legs want you to surrender. Same answer.",
                // Jog Lock's own: the count in a boxing film
                "You're down, not out. The count's at eight. Get up and finish this.",
                // William Ernest Henley, "Invictus" (1888)
                "I am the master of my fate, I am the captain of my soul. Right then, captain. Let's move.",
                // Rudyard Kipling, "If—" (1910)
                "Force your heart and nerve and sinew to serve your turn long after they are gone. Kipling again. Get going.",
                // Jog Lock's own: the rescue in a war film
                "Nobody gets left behind. That includes you. Let's go.",
                // Terence and Virgil: fortune favours the bold
                "Fortune favours the bold. It has never once favoured standing still. Go.",
            ]
        }
    }

    /// The line for a moment; `index` wraps, so a run can count up from any start.
    public static func line(_ moment: PepMoment, index: Int) -> String {
        let all = lines(for: moment)
        return all[((index % all.count) + all.count) % all.count]
    }

    /// Every line in turn, for Settings' sample button.
    public static func sample(index: Int) -> String {
        let all = PepMoment.allCases.flatMap(lines(for:))
        return all[((index % all.count) + all.count) % all.count]
    }
}
