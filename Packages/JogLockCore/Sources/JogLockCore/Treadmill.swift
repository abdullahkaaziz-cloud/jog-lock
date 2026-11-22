//
//  Treadmill.swift
//  JogLockCore
//
//  Treadmill mode: distance from steps, using a stride length learned on
//  GPS runs.
//
//  - Outdoor runs that pass the step check teach the stride model: in each
//    30-second window, step length = counted GPS distance / steps, against
//    cadence (steps per second). A straight line through those points gives
//    step length at any cadence; with too little spread in cadence it's the
//    median step length.
//  - On a treadmill, each pedometer update's new steps cover
//    steps x stepLength(cadence) metres. Without a model the iPhone's own
//    pedometer distance is used, and without that a short default step.
//  - Steps faster than maxCadence aren't counted, and the share of time
//    Core Motion is fairly sure the phone is in a car, on a bike or
//    standing still doesn't count.
//
//  Tools/treadmill.py is a line-for-line mirror of this file. If you change
//  the rules here, change them there too.
//

import Foundation

public enum RunMode: String, Codable, Sendable {
    case outdoor
    case treadmill
}

public struct StrideSample: Codable, Equatable, Sendable {
    public var cadence: Double   // steps per second
    public var length: Double    // metres per step

    public init(cadence: Double, length: Double) {
        self.cadence = cadence
        self.length = length
    }
}

public struct StrideModel: Codable, Equatable, Sendable {
    public static let minSamples = 10      // windows needed before the model is used
    public static let minStep = 0.3        // m: limits on any step length the model gives
    public static let maxStep = 2.0
    public static let maxSlope = 2.0       // m per (step/s): limit on how fast step length grows with cadence

    public var intercept: Double
    public var slope: Double
    public var minCadence: Double
    public var maxCadence: Double
    public var samples: Int

    public init(intercept: Double, slope: Double, minCadence: Double, maxCadence: Double, samples: Int) {
        self.intercept = intercept
        self.slope = slope
        self.minCadence = minCadence
        self.maxCadence = maxCadence
        self.samples = samples
    }

    /// Step length at a cadence, holding the cadence to the range the model learned.
    public func stepLength(cadence: Double) -> Double {
        let c = min(max(cadence, minCadence), maxCadence)
        return min(max(intercept + slope * c, Self.minStep), Self.maxStep)
    }

    /// Fits step length = intercept + slope x cadence, or nil with fewer than
    /// `minSamples` usable windows.
    public static func fit(_ samples: [StrideSample]) -> StrideModel? {
        let usable = samples.filter {
            $0.cadence >= 1.0 && $0.cadence <= 4.0 && $0.length >= minStep && $0.length <= maxStep
        }
        let n = usable.count
        guard n >= minSamples else { return nil }
        let cs = usable.map(\.cadence)
        let ls = usable.map(\.length)
        let meanC = cs.reduce(0, +) / Double(n)
        let meanL = ls.reduce(0, +) / Double(n)
        let variance = cs.reduce(0) { $0 + ($1 - meanC) * ($1 - meanC) } / Double(n)
        let slope: Double
        let intercept: Double
        if variance < 0.01 {
            // Cadence too steady (sd under 0.1 steps/s) to fit a slope.
            slope = 0
            intercept = median(ls)
        } else {
            var cov = 0.0
            for i in 0..<n {
                cov += (cs[i] - meanC) * (ls[i] - meanL)
            }
            cov /= Double(n)
            slope = min(max(cov / variance, 0), maxSlope)
            intercept = meanL - slope * meanC
        }
        return StrideModel(intercept: intercept, slope: slope,
                           minCadence: cs.min() ?? 0, maxCadence: cs.max() ?? 0, samples: n)
    }

    private static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        let n = v.count
        return n % 2 == 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2
    }
}

public enum StrideCalibration {
    /// Step length against cadence, from an outdoor run that passed the step
    /// check (at least `minCountedShare` of its GPS distance counted).
    public static func samples(from lines: [LogLine], window: Double = 30,
                               minCountedShare: Double = 0.9) -> [StrideSample] {
        var counter = RunCounter.replaying(lines)
        counter.finish()
        let clean = counter.engine.snapshot.cleanMeters
        guard clean > 0, counter.gate.totals.countedMeters >= minCountedShare * clean else { return [] }

        var steps: [(t: Double, n: Int)] = []
        for line in lines where line.type == "steps" {
            guard let n = line.steps else { continue }
            if let last = steps.last, !(line.t > last.t && n >= last.n) {
                continue
            }
            steps.append((line.t, n))
        }
        guard steps.count >= 2 else { return [] }

        var out: [StrideSample] = []
        var w = steps[0].t
        while w + window <= steps[steps.count - 1].t {
            if let s0 = interpolate(steps, at: w), let s1 = interpolate(steps, at: w + window) {
                let n = s1 - s0
                var d = 0.0
                for segment in counter.segments {
                    d += overlapMeters(segment, from: w, to: w + window)
                }
                if n >= 20 && d >= 30 {
                    out.append(StrideSample(cadence: n / window, length: d / n))
                }
            }
            w += window
        }
        return out
    }

    private static func interpolate(_ steps: [(t: Double, n: Int)], at t: Double) -> Double? {
        for i in 0..<(steps.count - 1) {
            let (t0, s0) = steps[i]
            let (t1, s1) = steps[i + 1]
            if t0 <= t && t <= t1 {
                return Double(s0) + Double(s1 - s0) * (t - t0) / (t1 - t0)
            }
        }
        return nil
    }

    private static func overlapMeters(_ segment: CountedSegment, from a: Double, to b: Double) -> Double {
        if segment.end <= segment.start {
            return a <= segment.end && segment.end < b ? segment.meters : 0
        }
        let overlap = max(0, min(segment.end, b) - max(segment.start, a))
        return segment.meters * overlap / (segment.end - segment.start)
    }
}

public struct TreadmillSettings: Codable, Equatable, Sendable {
    public var maxCadence: Double = 4.0                     // steps/s: steps faster than this don't count
    public var defaultStepLength: Double = 0.75             // m: with no model and no pedometer distance
    public var settleDelay: Double = 60                     // s: how long steps wait for late motion data
    public var stillConfidence: MotionConfidence = .medium  // this sure the phone is still: those steps don't count
    public var vehicleConfidence: MotionConfidence = .medium

    public static let standard = TreadmillSettings()

    public init() {}
}

public struct TreadmillCounter: Sendable {
    public let settings: TreadmillSettings
    public let model: StrideModel?

    /// countedMeters counts toward unlocking; vehicleMeters holds what was
    /// rejected (car, bike or standing still); noStepsMeters is always 0.
    public var totals: GateTotals {
        var t = GateTotals()
        t.countedMeters = counted
        t.vehicleMeters = rejected
        t.pendingMeters = pending.reduce(0) { $0 + distance($1) }
        t.steps = steps
        return t
    }

    private struct Interval: Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var steps: Int
        var pedMeters: Double?
    }

    private var counted = 0.0
    private var rejected = 0.0
    private var steps = 0
    private var pending: [Interval] = []
    private var motions: [MotionSample] = []
    private var stepTime: TimeInterval
    private var pedTotal = 0.0

    public init(start: TimeInterval, model: StrideModel? = nil, settings: TreadmillSettings = .standard) {
        self.settings = settings
        self.model = model
        stepTime = start
    }

    // MARK: - Inputs

    /// The pedometer's step count since the run started, and its own
    /// distance estimate (m) if it has one.
    public mutating func addSteps(_ sample: StepSample, pedMeters: Double? = nil) {
        if sample.steps > steps {
            var newPed: Double?
            if let pedMeters, pedMeters >= pedTotal {
                newPed = pedMeters - pedTotal
            }
            pending.append(Interval(start: stepTime, end: max(sample.t, stepTime),
                                    steps: sample.steps - steps, pedMeters: newPed))
            steps = sample.steps
        }
        if let pedMeters {
            pedTotal = max(pedTotal, pedMeters)
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

    /// Rebuilds a treadmill run from its log, line by line in the order
    /// written. Stops at the "stop" event. Call finish() afterwards for a
    /// finished run's totals.
    public static func replaying(_ lines: [LogLine]) -> TreadmillCounter {
        let header = lines.first(where: { $0.type == "header" })
        var counter = TreadmillCounter(start: header?.t ?? lines.first?.t ?? 0,
                                       model: header?.stride,
                                       settings: header?.treadmill ?? .standard)
        for line in lines {
            switch line.type {
            case "steps":
                if let steps = line.steps {
                    counter.addSteps(StepSample(t: line.t, steps: steps), pedMeters: line.pedMeters)
                }
            case "motion":
                if let kind = line.activity, let confidence = line.confidence {
                    counter.addMotion(MotionSample(start: line.t, kind: kind, confidence: confidence))
                }
            case "event" where line.name == "stop":
                return counter
            default:
                break
            }
        }
        return counter
    }

    // MARK: - Private

    private mutating func settle(final: Bool) {
        while let interval = pending.first {
            if !(final || stepTime >= interval.end + settings.settleDelay) {
                break
            }
            pending.removeFirst()
            let d = distance(interval)
            let bad = suspiciousShare(interval.start, interval.end)
            counted += d * (1 - bad)
            rejected += d * bad
        }
    }

    private func distance(_ interval: Interval) -> Double {
        let dt = interval.end - interval.start
        let n = dt <= 0 ? Double(interval.steps) : min(Double(interval.steps), settings.maxCadence * dt)
        if let model {
            return n * model.stepLength(cadence: dt > 0 ? n / dt : 0)
        }
        if let pedMeters = interval.pedMeters {
            return min(pedMeters * n / Double(interval.steps), n * StrideModel.maxStep)
        }
        return n * settings.defaultStepLength
    }

    private func suspicious(_ m: MotionSample) -> Bool {
        if m.kind.isVehicle {
            return m.confidence >= settings.vehicleConfidence
        }
        if m.kind == .stationary {
            return m.confidence >= settings.stillConfidence
        }
        return false
    }

    /// Share of [start, end] during which a suspicious activity was in effect.
    private func suspiciousShare(_ start: TimeInterval, _ end: TimeInterval) -> Double {
        if end <= start {
            var current: MotionSample?
            for m in motions {
                if m.start > start {
                    break
                }
                current = m
            }
            if let current, suspicious(current) {
                return 1
            }
            return 0
        }
        var bad = 0.0
        for (i, m) in motions.enumerated() {
            let until = i + 1 < motions.count ? motions[i + 1].start : Double.infinity
            let overlap = min(end, until) - max(start, m.start)
            if overlap > 0 && suspicious(m) {
                bad += overlap
            }
        }
        return min(1, bad / (end - start))
    }
}
