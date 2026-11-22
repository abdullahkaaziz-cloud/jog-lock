//
//  StepGate.swift
//  JogLockCore
//
//  Anti-cheat: only GPS distance backed by steps, and not covered in a car
//  or on a bike, counts toward unlocking.
//
//  - Every new step from the pedometer adds "credit": steps x maxStepLength
//    metres, spread over the time those steps were taken.
//  - Each piece of GPS distance the engine counts waits settleDelay seconds,
//    so late step and motion data can arrive, then spends credit from steps
//    taken within matchWindow of it, nearest in time first. Whatever credit
//    can't cover is "no steps".
//  - Distance while Core Motion is reasonably sure the phone is in a car or
//    on a bike is "vehicle", whatever the steps say.
//  - If the pedometer goes quiet for stallLimit seconds while GPS keeps
//    counting, the waiting distance is settled anyway, as no steps.
//
//  Tools/stepgate.py is a line-for-line mirror of this file. If you change
//  the rules here, change them there too.
//

import Foundation

/// What Core Motion thinks the phone is doing.
public enum MotionKind: String, Codable, Sendable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown

    public var isVehicle: Bool {
        self == .cycling || self == .automotive
    }
}

public enum MotionConfidence: Int, Codable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: MotionConfidence, rhs: MotionConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// An activity from Core Motion, in effect from `start` until the next one.
public struct MotionSample: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var kind: MotionKind
    public var confidence: MotionConfidence

    public init(start: TimeInterval, kind: MotionKind, confidence: MotionConfidence) {
        self.start = start
        self.kind = kind
        self.confidence = confidence
    }
}

/// The pedometer's step count since the run started, as of time `t`.
public struct StepSample: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var steps: Int

    public init(t: TimeInterval, steps: Int) {
        self.t = t
        self.steps = steps
    }
}

public struct StepGateSettings: Codable, Equatable, Sendable {
    public var maxStepLength: Double = 2.0                   // m: more GPS distance per step isn't on foot
    public var matchWindow: Double = 5                       // s: steps this far either side can back distance
    public var settleDelay: Double = 60                      // s: how long distance waits for late data
    public var stallLimit: Double = 120                      // s: GPS this far past the last step update settles as no steps
    public var vehicleConfidence: MotionConfidence = .medium // this sure of a car or bike rejects distance

    public static let standard = StepGateSettings()

    public init() {}
}

public struct GateTotals: Equatable, Sendable {
    public var countedMeters: Double = 0    // backed by steps: counts toward unlocking
    public var noStepsMeters: Double = 0    // not enough steps to have covered it on foot
    public var vehicleMeters: Double = 0    // covered while in a car or on a bike
    public var pendingMeters: Double = 0    // still waiting for step and motion data
    public var steps: Int = 0

    public init() {}
}

public struct StepGate: Sendable {
    public let settings: StepGateSettings

    public var totals: GateTotals {
        var t = settled
        t.pendingMeters = pending.reduce(0) { $0 + $1.meters }
        return t
    }

    private struct Segment: Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var meters: Double
    }

    private struct Credit: Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var meters: Double
    }

    private var settled = GateTotals()
    private var pending: [Segment] = []
    private var credits: [Credit] = []
    private var motions: [MotionSample] = []
    private var stepTime: TimeInterval   // newest pedometer time (the run start until the first update)
    private var gpsTime: TimeInterval    // end of the newest GPS distance

    public init(start: TimeInterval, settings: StepGateSettings = .standard) {
        self.settings = settings
        stepTime = start
        gpsTime = start
    }

    // MARK: - Inputs

    public mutating func addDistance(_ meters: Double, from start: TimeInterval, to end: TimeInterval) {
        guard meters > 0 else { return }
        pending.append(Segment(start: start, end: end, meters: meters))
        gpsTime = max(gpsTime, end)
        settle(final: false)
    }

    public mutating func addSteps(_ sample: StepSample) {
        if sample.steps > settled.steps {
            let new = sample.steps - settled.steps
            credits.append(Credit(start: stepTime, end: max(sample.t, stepTime),
                                  meters: Double(new) * settings.maxStepLength))
            settled.steps = sample.steps
        }
        stepTime = max(stepTime, sample.t)
        settle(final: false)
    }

    /// Returns false if the same sample was already added.
    @discardableResult
    public mutating func addMotion(_ sample: MotionSample) -> Bool {
        guard !motions.contains(sample) else { return false }
        var i = motions.count
        while i > 0 && motions[i - 1].start > sample.start {
            i -= 1
        }
        motions.insert(sample, at: i)
        return true
    }

    /// Settles everything. Call once at the end of the run.
    public mutating func finish() {
        settle(final: true)
    }

    // MARK: - Private

    private mutating func settle(final: Bool) {
        let s = settings
        while let seg = pending.first {
            let ready = final || stepTime >= seg.end + s.settleDelay || gpsTime >= seg.end + s.stallLimit
            if !ready {
                break
            }
            pending.removeFirst()
            dropOldMotions(before: seg.start)
            if inVehicle(seg.start, seg.end) {
                settled.vehicleMeters += seg.meters
                continue
            }
            // Credit too old to back this distance can't back any later distance either.
            let lo = seg.start - s.matchWindow
            let hi = seg.end + s.matchWindow
            credits.removeAll { $0.end < lo || $0.meters <= 0 }
            let mid = (seg.start + seg.end) / 2
            let nearby = credits.indices
                .filter { credits[$0].start <= hi }
                .sorted { a, b in
                    let da = abs((credits[a].start + credits[a].end) / 2 - mid)
                    let db = abs((credits[b].start + credits[b].end) / 2 - mid)
                    return da != db ? da < db : credits[a].start < credits[b].start
                }
            var need = seg.meters
            for i in nearby {
                if need <= 0 {
                    break
                }
                let take = min(credits[i].meters, need)
                credits[i].meters -= take
                need -= take
            }
            settled.countedMeters += seg.meters - need
            settled.noStepsMeters += need
        }
    }

    private mutating func dropOldMotions(before t: TimeInterval) {
        // Keep the activity in effect at `t` and everything after it.
        while motions.count >= 2 && motions[1].start <= t {
            motions.removeFirst()
        }
    }

    private func inVehicle(_ start: TimeInterval, _ end: TimeInterval) -> Bool {
        if let current = effective(at: start), isVehicle(current) {
            return true
        }
        for m in motions {
            if m.start >= end {
                break
            }
            if m.start > start && isVehicle(m) {
                return true
            }
        }
        return false
    }

    private func effective(at t: TimeInterval) -> MotionSample? {
        var current: MotionSample?
        for m in motions {
            if m.start > t {
                break
            }
            current = m
        }
        return current
    }

    private func isVehicle(_ m: MotionSample) -> Bool {
        m.kind.isVehicle && m.confidence >= settings.vehicleConfidence
    }
}
