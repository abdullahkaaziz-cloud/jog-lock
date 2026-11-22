//
//  RunCounter.swift
//  JogLockCore
//
//  The distance engine and the step gate together, fed in the order the
//  phone received its inputs. The app uses it live, and to pick a run back
//  up from its log after iOS relaunches the app. replay_gated() in
//  Tools/replay.py does the same in Python.
//

import Foundation

public struct RunCounter: Sendable {
    public private(set) var engine: DistanceEngine
    public private(set) var gate: StepGate
    /// Every piece of distance the engine counted, in order.
    public private(set) var segments: [CountedSegment] = []

    public init(start: TimeInterval,
                settings: EngineSettings = .standard,
                gateSettings: StepGateSettings = .standard) {
        engine = DistanceEngine(settings: settings)
        gate = StepGate(start: start, settings: gateSettings)
    }

    @discardableResult
    public mutating func add(_ fix: GPSFix) -> FixDecision {
        let decision = engine.process(fix)
        countLastSegment()
        return decision
    }

    public mutating func addSteps(_ sample: StepSample) {
        gate.addSteps(sample)
    }

    /// Returns false if the same sample was already added.
    @discardableResult
    public mutating func addMotion(_ sample: MotionSample) -> Bool {
        gate.addMotion(sample)
    }

    /// Ends the run: counts the engine's last partial segment, then settles
    /// all the distance still waiting for step data.
    public mutating func finish() {
        engine.finalize()
        countLastSegment()
        gate.finish()
    }

    private mutating func countLastSegment() {
        if let seg = engine.lastSegment {
            gate.addDistance(seg.meters, from: seg.start, to: seg.end)
            segments.append(seg)
        }
    }

    /// Rebuilds a run from its log, line by line in the order written.
    /// Stops at the "stop" event. Call finish() afterwards for a finished
    /// run's totals.
    public static func replaying(_ lines: [LogLine]) -> RunCounter {
        let header = lines.first(where: { $0.type == "header" })
        var counter = RunCounter(start: header?.t ?? lines.first?.t ?? 0,
                                 settings: header?.settings ?? .standard,
                                 gateSettings: header?.gate ?? .standard)
        for line in lines {
            switch line.type {
            case "fix":
                if let fix = GPSFix(line: line) {
                    counter.add(fix)
                }
            case "steps":
                if let steps = line.steps {
                    counter.addSteps(StepSample(t: line.t, steps: steps))
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
}
