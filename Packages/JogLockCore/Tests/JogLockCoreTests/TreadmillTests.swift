import Foundation
import Testing
@testable import JogLockCore

private let t0: TimeInterval = 1_700_000_000
private let model = StrideModel(intercept: 0.5, slope: 0.2, minCadence: 2.2, maxCadence: 3.2, samples: 40)

/// Steady pedometer updates every `every` seconds, like Tools/test_treadmill.py.
private func treadmillRun(_ counter: inout TreadmillCounter, seconds: Int, cadence: Double,
                          every: Double = 2.5, pedPerStep: Double? = nil) {
    let updates = Int(Double(seconds) / every)
    for k in stride(from: 1, through: updates, by: 1) {
        let n = Int(cadence * every * Double(k))
        counter.addSteps(StepSample(t: t0 + every * Double(k), steps: n),
                         pedMeters: pedPerStep.map { Double(n) * $0 })
    }
}

private func fixture(_ name: String) throws -> [LogLine] {
    let url = RunFixtureTests.fixtures.appendingPathComponent(name)
    return RunCoding.decodeLines(try String(contentsOf: url, encoding: .utf8))
}

/// Same scenarios and numbers as Tools/test_treadmill.py.
@Suite("Stride model")
struct StrideModelTests {
    @Test("Steady cadence gives a flat model at the median step")
    func steadyCadence() throws {
        let lengths = [1.0, 1.1, 1.05, 0.95, 1.2, 1.0, 1.1, 0.9, 1.05, 1.15, 1.0]
        let fitted = try #require(StrideModel.fit(lengths.map { StrideSample(cadence: 2.7, length: $0) }))
        #expect(fitted.slope == 0)
        #expect(fitted.intercept == 1.05)
    }

    @Test("Spread in cadence fits step length = 0.5 + 0.2 x cadence")
    func recoversALine() throws {
        let samples = (0...10).map { i -> StrideSample in
            let c = 2.2 + 0.1 * Double(i)
            return StrideSample(cadence: c, length: 0.5 + 0.2 * c)
        }
        let fitted = try #require(StrideModel.fit(samples))
        #expect(abs(fitted.slope - 0.2) < 1e-9)
        #expect(abs(fitted.intercept - 0.5) < 1e-9)
    }

    @Test("Fewer than 10 usable windows gives no model")
    func needsTenSamples() {
        #expect(StrideModel.fit(Array(repeating: StrideSample(cadence: 2.7, length: 1.0), count: 9)) == nil)
    }

    @Test("Cadence is held to the learned range, step length to 0.3-2.0 m")
    func limits() {
        #expect(abs(model.stepLength(cadence: 5.0) - (0.5 + 0.2 * 3.2)) < 1e-12)
        #expect(abs(model.stepLength(cadence: 1.0) - (0.5 + 0.2 * 2.2)) < 1e-12)
        let wild = StrideModel(intercept: -3, slope: 2, minCadence: 1, maxCadence: 4, samples: 10)
        #expect(wild.stepLength(cadence: 1) == 0.3)
        #expect(wild.stepLength(cadence: 4) == 2.0)
    }

    @Test("Learns the stride that generated the honest run, the same model Python recorded")
    func honestFixture() throws {
        let lines = try fixture("synthetic-honest-run.jsonl")
        let fitted = try #require(StrideModel.fit(StrideCalibration.samples(from: lines)))
        let recorded = try #require(lines.last?.stride)
        #expect(abs(fitted.slope - 0.2) < 0.02)
        #expect(abs(fitted.intercept - 0.5) < 0.05)
        #expect(abs(fitted.slope - recorded.slope) < 1e-9)
        #expect(abs(fitted.intercept - recorded.intercept) < 1e-9)
        #expect(fitted.samples == recorded.samples)
    }

    @Test("A run that failed the step check teaches nothing")
    func failedRunTeachesNothing() throws {
        #expect(StrideCalibration.samples(from: try fixture("synthetic-gated-run.jsonl")).isEmpty)
    }
}

@Suite("TreadmillCounter")
struct TreadmillCounterTests {
    @Test("With a stride model: steps x step length at that cadence")
    func modelDistance() {
        var counter = TreadmillCounter(start: t0, model: model)
        treadmillRun(&counter, seconds: 600, cadence: 2.8)
        counter.finish()
        let totals = counter.totals
        #expect(abs(totals.countedMeters - Double(totals.steps) * (0.5 + 0.2 * 2.8)) < 1e-6)
    }

    @Test("Without a model: the iPhone's own pedometer distance")
    func pedometerDistance() {
        var counter = TreadmillCounter(start: t0)
        treadmillRun(&counter, seconds: 600, cadence: 2.8, pedPerStep: 0.8)
        counter.finish()
        let totals = counter.totals
        #expect(abs(totals.countedMeters - Double(totals.steps) * 0.8) < 1e-6)
    }

    @Test("Without a model or pedometer distance: 0.75 m a step")
    func defaultStep() {
        var counter = TreadmillCounter(start: t0)
        treadmillRun(&counter, seconds: 600, cadence: 2.8)
        counter.finish()
        let totals = counter.totals
        #expect(abs(totals.countedMeters - Double(totals.steps) * 0.75) < 1e-6)
    }

    @Test("Steps faster than 4 a second don't count")
    func cadenceCap() {
        var counter = TreadmillCounter(start: t0, model: model)
        treadmillRun(&counter, seconds: 60, cadence: 6)
        counter.finish()
        #expect(counter.totals.countedMeters <= 4 * 60 * model.stepLength(cadence: 4) + 1e-6)
    }

    @Test("Half the time 'standing still' rejects half the distance")
    func standingStillShare() {
        var counter = TreadmillCounter(start: t0, model: model)
        counter.addMotion(MotionSample(start: t0, kind: .running, confidence: .high))
        counter.addMotion(MotionSample(start: t0 + 150, kind: .stationary, confidence: .high))
        counter.addSteps(StepSample(t: t0 + 300, steps: 840))
        counter.finish()
        let total = 840 * model.stepLength(cadence: 840.0 / 300)
        #expect(abs(counter.totals.vehicleMeters - total / 2) < 1e-6)
    }

    @Test("A car rejects everything; a low-confidence 'still' rejects nothing")
    func vehicleAndLowConfidence() {
        var car = TreadmillCounter(start: t0, model: model)
        car.addMotion(MotionSample(start: t0, kind: .automotive, confidence: .high))
        treadmillRun(&car, seconds: 120, cadence: 2.8)
        car.finish()
        var still = TreadmillCounter(start: t0, model: model)
        still.addMotion(MotionSample(start: t0, kind: .stationary, confidence: .low))
        treadmillRun(&still, seconds: 120, cadence: 2.8)
        still.finish()
        #expect(car.totals.countedMeters == 0)
        #expect(still.totals.vehicleMeters == 0)
    }

    @Test("The last minute waits for late motion data")
    func pendingUntilSettled() {
        var counter = TreadmillCounter(start: t0, model: model)
        treadmillRun(&counter, seconds: 300, cadence: 2.8)
        let waiting = counter.totals.pendingMeters
        #expect(waiting > 0 && waiting <= 61 * 2.8 * model.stepLength(cadence: 2.8))
    }

    @Test("The treadmill fixture replays to the totals Python recorded")
    func fixtureParity() throws {
        let lines = try fixture("synthetic-treadmill-run.jsonl")
        let stop = try #require(lines.last)
        var counter = TreadmillCounter.replaying(lines)
        counter.finish()
        let totals = counter.totals
        #expect(abs(totals.countedMeters - (stop.counted ?? -1)) < 0.01)
        #expect(abs(totals.vehicleMeters - (stop.rejected ?? -1)) < 0.01)
        #expect(totals.steps == stop.steps)
    }
}
