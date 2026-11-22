import Foundation
import Testing
@testable import JogLockCore

private let t0: TimeInterval = 1_700_000_000

/// Plays GPS distance and pedometer updates into a gate in time order, the
/// same way Tools/test_stepgate.py does. GPS distance arrives every 2 s; the
/// pedometer reports its running total every `stepEvery` seconds.
private struct GateFeed {
    var gate: StepGate
    var t: TimeInterval = t0
    var steps = 0.0
    var gpsMeters = 0.0

    init(_ gate: StepGate) {
        self.gate = gate
    }

    mutating func move(seconds: Int, speed: Double, cadence: Double, stepEvery: Double = 2.5, gps: Bool = true) {
        var events: [(t: TimeInterval, order: Int, value: Double)] = []
        if gps {
            for k in stride(from: 1, through: seconds / 2, by: 1) {
                events.append((t + 2 * Double(k), 0, speed * 2))
            }
        }
        let steps0 = steps
        let count = Int(Double(seconds) / stepEvery)
        for k in stride(from: 1, through: count, by: 1) {
            let total = Int(steps0 + cadence * stepEvery * Double(k))
            events.append((t + stepEvery * Double(k), 1, Double(total)))
        }
        events.sort { ($0.t, $0.order) < ($1.t, $1.order) }
        for event in events {
            if event.order == 0 {
                gate.addDistance(event.value, from: event.t - 2, to: event.t)
                gpsMeters += event.value
            } else {
                gate.addSteps(StepSample(t: event.t, steps: Int(event.value)))
            }
        }
        steps = steps0 + cadence * Double(seconds)
        t += Double(seconds)
    }
}

/// Same scenarios and limits as Tools/test_stepgate.py.
@Suite("StepGate")
struct StepGateTests {
    @Test("A jog with steps counts in full once the late data has arrived")
    func honestJog() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 600, speed: 3, cadence: 2.7)
        let waiting = feed.gate.totals.pendingMeters
        #expect(waiting > 0 && waiting <= 3 * 62)
        feed.gate.finish()
        let totals = feed.gate.totals
        #expect(abs(totals.countedMeters - 1800) < 1e-6)
        #expect(totals.noStepsMeters == 0)
        #expect(totals.pendingMeters == 0)
    }

    @Test("With no step data nothing counts")
    func noStepData() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 300, speed: 3, cadence: 0)
        feed.gate.finish()
        let totals = feed.gate.totals
        #expect(totals.countedMeters == 0)
        #expect(abs(totals.noStepsMeters - 900) < 1e-6)
    }

    @Test("Driving with a shaken phone is rejected as a vehicle")
    func drivingWithShakenPhone() {
        var gate = StepGate(start: t0)
        gate.addMotion(MotionSample(start: t0, kind: .automotive, confidence: .high))
        var feed = GateFeed(gate)
        feed.move(seconds: 300, speed: 8, cadence: 3)
        feed.gate.finish()
        let totals = feed.gate.totals
        #expect(totals.countedMeters == 0)
        #expect(abs(totals.vehicleMeters - 2400) < 1e-6)
    }

    @Test("A low-confidence 'car' doesn't block a real jog")
    func lowConfidenceVehicle() {
        var gate = StepGate(start: t0)
        gate.addMotion(MotionSample(start: t0, kind: .automotive, confidence: .low))
        var feed = GateFeed(gate)
        feed.move(seconds: 300, speed: 3, cadence: 2.7)
        feed.gate.finish()
        #expect(abs(feed.gate.totals.countedMeters - 900) < 1e-6)
    }

    @Test("Cycling with few steps counts under 15%")
    func cycling() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 300, speed: 5, cadence: 0.3)
        feed.gate.finish()
        #expect(feed.gate.totals.countedMeters / 1500 < 0.15)
    }

    @Test("Steps reported only every 20 s still count in full")
    func batchedSteps() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 600, speed: 3, cadence: 2.7, stepEvery: 20)
        feed.gate.finish()
        #expect(abs(feed.gate.totals.countedMeters - 1800) < 1e-6)
    }

    @Test("Steps from before GPS back at most a few seconds of later driving")
    func indoorStepsDontCarryOver() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 300, speed: 0, cadence: 2, gps: false)
        feed.move(seconds: 120, speed: 8, cadence: 0)
        feed.gate.finish()
        // match window plus one pedometer interval: (5 + 2.5) s x 2 steps/s x 2 m
        #expect(feed.gate.totals.countedMeters <= 2 * 7.5 * 2.0 + 1e-6)
    }

    @Test("Alternating jogging and driving adds under 10% of the driven distance")
    func alternatingJogAndDrive() {
        var feed = GateFeed(StepGate(start: t0))
        var jog = 0.0
        var drive = 0.0
        for _ in 0..<5 {
            var before = feed.gpsMeters
            feed.move(seconds: 60, speed: 3, cadence: 2.7)
            jog += feed.gpsMeters - before
            before = feed.gpsMeters
            feed.move(seconds: 60, speed: 8, cadence: 0)
            drive += feed.gpsMeters - before
        }
        feed.gate.finish()
        #expect(feed.gate.totals.countedMeters - jog < 0.1 * drive)
    }

    @Test("When the pedometer goes quiet, waiting distance settles as too few steps")
    func stalledPedometer() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 60, speed: 3, cadence: 2.7)
        feed.move(seconds: 240, speed: 3, cadence: 0)
        #expect(feed.gate.totals.noStepsMeters > 0)
    }

    @Test("A step count that goes down is ignored")
    func stepCountGoingDown() {
        var gate = StepGate(start: t0)
        gate.addSteps(StepSample(t: t0 + 10, steps: 30))
        gate.addSteps(StepSample(t: t0 + 12, steps: 20))
        gate.addSteps(StepSample(t: t0 + 14, steps: 36))
        #expect(gate.totals.steps == 36)
    }

    @Test("A car Core Motion notices late still rejects the distance since it started")
    func lateVehicleSample() {
        var feed = GateFeed(StepGate(start: t0))
        feed.move(seconds: 100, speed: 3, cadence: 2.7)
        feed.move(seconds: 20, speed: 8, cadence: 2.7)
        feed.gate.addMotion(MotionSample(start: t0 + 100, kind: .automotive, confidence: .medium))
        feed.move(seconds: 100, speed: 8, cadence: 2.7)
        feed.gate.finish()
        let totals = feed.gate.totals
        #expect(abs(totals.vehicleMeters - 960) < 1e-6)
        #expect(abs(totals.countedMeters - 300) < 1e-6)
    }

    @Test("The same motion sample is only added once")
    func duplicateMotion() {
        var gate = StepGate(start: t0)
        let sample = MotionSample(start: t0, kind: .running, confidence: .high)
        let first = gate.addMotion(sample)
        let second = gate.addMotion(sample)
        #expect(first)
        #expect(!second)
    }
}

@Suite("RunCounter")
struct RunCounterTests {
    @Test("Every counted segment reaches the gate, so its distance adds up to the engine's")
    func segmentsReachTheGate() {
        var track = TrackBuilder()
        track.run(seconds: 300, speed: 3)
        var counter = RunCounter(start: track.fixes[0].t - 1)
        var segmentMeters = 0.0
        for fix in track.fixes {
            let decision = counter.add(fix)
            if decision == .accepted, let segment = counter.engine.lastSegment {
                #expect(segment.end == fix.t)
                #expect(segment.start < segment.end)
                segmentMeters += segment.meters
            } else {
                #expect(counter.engine.lastSegment == nil)
            }
        }
        counter.finish()
        let totals = counter.gate.totals
        let gated = totals.countedMeters + totals.noStepsMeters + totals.vehicleMeters
        #expect(abs(gated - counter.engine.snapshot.cleanMeters) < 1e-6)
        #expect(segmentMeters <= counter.engine.snapshot.cleanMeters)
    }

    @Test("Replaying the synthetic gated run gives the totals Python recorded")
    func gatedFixtureParity() throws {
        let url = RunFixtureTests.fixtures.appendingPathComponent("synthetic-gated-run.jsonl")
        let lines = RunCoding.decodeLines(try String(contentsOf: url, encoding: .utf8))
        let stop = try #require(lines.first(where: { $0.type == "event" && $0.name == "stop" }))
        var counter = RunCounter.replaying(lines)
        counter.finish()
        let totals = counter.gate.totals
        #expect(abs(totals.countedMeters - (stop.counted ?? -1)) < 0.01)
        #expect(abs(totals.noStepsMeters - (stop.noSteps ?? -1)) < 0.01)
        #expect(abs(totals.vehicleMeters - (stop.vehicle ?? -1)) < 0.01)
        #expect(abs(counter.engine.snapshot.cleanMeters - (stop.clean ?? -1)) < 0.01)
        #expect(totals.steps == stop.steps)
        #expect(totals.countedMeters > 0 && totals.noStepsMeters > 0 && totals.vehicleMeters > 0)
    }
}
