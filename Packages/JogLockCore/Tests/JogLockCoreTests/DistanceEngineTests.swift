import Foundation
import Testing
@testable import JogLockCore

@Suite("DistanceEngine")
struct DistanceEngineTests {
    @Test("Counting starts after three good fixes in a row")
    func warmUp() {
        var track = TrackBuilder()
        track.run(seconds: 10, speed: 3)
        var engine = DistanceEngine()
        let decisions = engine.process(track.fixes)
        #expect(decisions[0] == .warmingUp)
        #expect(decisions[1] == .warmingUp)
        #expect(decisions[2] == .warmupComplete)
        #expect(engine.snapshot.phase == .tracking)
    }

    @Test("A weak fix during warm-up restarts the count")
    func warmUpRestarts() {
        var track = TrackBuilder()
        track.run(seconds: 2, speed: 3)
        track.accuracy = 40
        track.run(seconds: 1, speed: 3)
        track.accuracy = 5
        track.run(seconds: 3, speed: 3)
        var engine = DistanceEngine()
        let decisions = engine.process(track.fixes)
        #expect(decisions.firstIndex(of: .warmupComplete) == 5)
    }

    @Test("A steady 10-minute jog counts its whole length")
    func steadyJog() throws {
        var track = TrackBuilder()
        track.run(seconds: 600, speed: 3)
        var engine = DistanceEngine()
        engine.process(track.fixes)
        let result = engine.finalize()
        let last = try #require(track.fixes.last)
        let expected = Geo.distance(track.fixes[2], last)  // counting starts at the third fix
        #expect(abs(result.cleanMeters - expected) < 0.5)
        #expect(abs(result.movingSeconds - 597) <= 2)
        #expect(result.rawMeters >= result.cleanMeters)
    }

    @Test("Fixes worse than the accuracy limit are skipped")
    func lowAccuracy() throws {
        var track = TrackBuilder()
        track.run(seconds: 60, speed: 3)
        track.accuracy = 50
        track.run(seconds: 10, speed: 3)
        track.accuracy = 5
        track.run(seconds: 60, speed: 3)
        var engine = DistanceEngine()
        engine.process(track.fixes)
        let result = engine.finalize()
        let last = try #require(track.fixes.last)
        #expect(result.rejected[FixDecision.rejectedLowAccuracy.rawValue] == 10)
        #expect(abs(result.cleanMeters - Geo.distance(track.fixes[2], last)) < 0.5)
    }

    @Test("One fix that jumps 300 m sideways is ignored")
    func singleJump() throws {
        var track = TrackBuilder()
        track.run(seconds: 60, speed: 3)
        track.t += 1
        track.north += 3
        track.append(track.fix(offsetEast: 300, offsetNorth: 0, speed: 3, stationary: false))
        track.run(seconds: 60, speed: 3)
        var engine = DistanceEngine()
        let decisions = engine.process(track.fixes)
        let result = engine.finalize()
        let last = try #require(track.fixes.last)
        #expect(decisions[60] == .rejectedJump)
        #expect(abs(result.cleanMeters - Geo.distance(track.fixes[2], last)) < 0.5)
    }

    @Test("Three jumps in a row re-anchor at the new position without counting the jump")
    func repeatedJumps() {
        var track = TrackBuilder()
        track.run(seconds: 30, speed: 3)
        track.east = 500
        track.run(seconds: 5, speed: 3)
        var engine = DistanceEngine()
        let decisions = engine.process(track.fixes)
        #expect(decisions[30] == .rejectedJump)
        #expect(decisions[31] == .rejectedJump)
        #expect(decisions[32] == .jumpReset)
        #expect(engine.snapshot.cleanMeters < 100)
    }

    @Test("Standing still with the iOS stationary flag adds nothing")
    func stationaryFlag() throws {
        var track = TrackBuilder()
        track.run(seconds: 60, speed: 3)
        let lastMoving = try #require(track.fixes.last)
        var rng = SplitMix64(seed: 1)
        var error = WanderingError()
        track.stand(seconds: 120, error: &error, rng: &rng, reportSpeed: true, stationaryFlag: true)
        var engine = DistanceEngine()
        engine.process(track.fixes)
        let result = engine.finalize()
        #expect(abs(result.cleanMeters - Geo.distance(track.fixes[2], lastMoving)) < 6)
    }

    @Test("Five minutes of GPS wander while standing adds under 30 m", arguments: 1...10)
    func standingDrift(seed: Int) {
        var track = TrackBuilder()
        var rng = SplitMix64(seed: UInt64(seed))
        var error = WanderingError()
        track.stand(seconds: 300, error: &error, rng: &rng, reportSpeed: false)
        var engine = DistanceEngine()
        engine.process(track.fixes)
        let result = engine.finalize()
        #expect(result.cleanMeters < 30)
    }

    @Test("A long GPS gap is not bridged")
    func gapNotBridged() throws {
        var track = TrackBuilder()
        track.run(seconds: 60, speed: 3)
        let beforeGap = try #require(track.fixes.last)
        track.skip(seconds: 200, speed: 3)
        track.run(seconds: 60, speed: 3)
        var engine = DistanceEngine()
        let decisions = engine.process(track.fixes)
        let result = engine.finalize()
        let afterGap = track.fixes[60]
        let last = try #require(track.fixes.last)
        let expected = Geo.distance(track.fixes[2], beforeGap) + Geo.distance(afterGap, last)
        #expect(decisions[60] == .gapReset)
        #expect(abs(result.cleanMeters - expected) < 6)  // up to one pending step is lost at the gap
    }

    @Test("Out-of-order and invalid fixes are rejected")
    func outOfOrderAndInvalid() {
        var track = TrackBuilder()
        track.run(seconds: 10, speed: 3)
        var engine = DistanceEngine()
        engine.process(track.fixes)
        var stale = track.fixes[4]
        stale.lat += 0.001
        let staleDecision = engine.process(stale)
        var invalid = track.fix(offsetEast: 0, offsetNorth: 3, speed: 3, stationary: false)
        invalid.t += 1
        invalid.hAcc = -1
        let invalidDecision = engine.process(invalid)
        #expect(staleDecision == .rejectedOutOfOrder)
        #expect(invalidDecision == .rejectedInvalid)
    }

    @Test("The speed-based estimate follows the reported speed")
    func speedEstimate() {
        var track = TrackBuilder()
        track.run(seconds: 300, speed: 3)
        var engine = DistanceEngine()
        engine.process(track.fixes)
        let result = engine.finalize()
        #expect(abs(result.speedMeters - 3 * 297) < 3)
    }
}
