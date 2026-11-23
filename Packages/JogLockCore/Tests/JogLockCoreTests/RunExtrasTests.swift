import Foundation
import Testing
@testable import JogLockCore

@Suite("Route")
struct RouteTests {
    @Test("The real run's route follows the counted points and splits at restarts")
    func fixtureRoute() throws {
        let lines = RunCoding.decodeLines(try String(contentsOf: RunFixtureTests.fixture, encoding: .utf8))
        let segments = Route.segments(from: lines)
        let counted = lines.filter { ["warmupComplete", "accepted", "gapReset", "jumpReset"].contains($0.decision ?? "") }
        #expect(!segments.isEmpty)
        #expect(segments.reduce(0) { $0 + $1.count } == counted.count)
    }

    @Test("A builder starts a new segment at a gap and keeps adding accepted points")
    func builder() {
        var builder = RouteBuilder()
        builder.add(Coordinate(lat: 51.5, lon: -0.12), decision: .warmupComplete)
        builder.add(Coordinate(lat: 51.5001, lon: -0.12), decision: .accepted)
        builder.add(Coordinate(lat: 51.5002, lon: -0.12), decision: .pending)
        builder.add(Coordinate(lat: 51.51, lon: -0.12), decision: .gapReset)
        builder.add(Coordinate(lat: 51.5101, lon: -0.12), decision: .accepted)
        #expect(builder.segments.map(\.count) == [2, 2])
    }

    @Test("Projection fits the route in the box, north up, keeping proportions")
    func projection() throws {
        // 1 km north and about 0.5 km east (at 51.5 N)
        let route = [[Coordinate(lat: 51.5, lon: -0.12), Coordinate(lat: 51.509, lon: -0.12),
                      Coordinate(lat: 51.509, lon: -0.1128)]]
        let points = try #require(Route.project(route, width: 200, height: 400, padding: 20).first)
        #expect(points.count == 3)
        for p in points {
            #expect(p.x >= 20 - 1e-9 && p.x <= 180 + 1e-9)
            #expect(p.y >= 20 - 1e-9 && p.y <= 380 + 1e-9)
        }
        #expect(points[1].y < points[0].y)     // north is up
        #expect(points[2].x > points[1].x)     // east is right
        let tall = abs(points[1].y - points[0].y)
        let wide = abs(points[2].x - points[1].x)
        #expect(abs(wide / tall - 0.5) < 0.05)  // proportions kept
    }

    @Test("A single point lands in the middle")
    func singlePoint() {
        let points = Route.project([[Coordinate(lat: 1, lon: 2)]], width: 100, height: 50)
        #expect(points == [[Point2D(x: 50, y: 25)]])
    }
}

@Suite("Voice coach")
struct VoiceCoachTests {
    @Test("A 2.5 km run hears progress, halfway, nearly there and the unlock, each once")
    func cuesForARun() {
        var planner = VoiceCoachPlanner()
        var cues: [VoiceCue] = []
        var meters = 0.0
        while meters <= 2_700 {
            if let cue = planner.cue(meters: meters, target: 2_500, unlocked: meters >= 2_500) {
                cues.append(cue)
            }
            meters += 10
        }
        #expect(cues == [
            .progress(meters: 500), .progress(meters: 1_000), .halfway, .progress(meters: 1_500),
            .progress(meters: 2_000), .almostThere, .unlocked,
        ])
    }

    @Test("Without a target it just counts every 500 m")
    func noTarget() {
        var planner = VoiceCoachPlanner()
        let cues = [0.0, 499, 500, 900, 1_000, 1_000].compactMap { planner.cue(meters: $0, target: 0, unlocked: false) }
        #expect(cues == [.progress(meters: 500), .progress(meters: 1_000)])
    }

    @Test("After the unlock, each extra 500 m is a bonus")
    func bonus() {
        var planner = VoiceCoachPlanner()
        _ = planner.cue(meters: 1_000, target: 1_000, unlocked: true)
        let next = planner.cue(meters: 1_500, target: 1_000, unlocked: true)
        #expect(next == .bonus(meters: 1_500))
    }

    @Test("Lines name the app and say the distance naturally")
    func lines() {
        let line = VoiceLines.text(for: .progress(meters: 500), app: "TikTok", remainingMeters: 1_820, variant: 0)
        #expect(line == "TikTok is getting closer. 1.8 kilometres to go.")
        #expect(VoiceLines.spoken(meters: 730) == "750 metres")
        #expect(VoiceLines.spoken(meters: 2_000) == "2 kilometres")
        #expect(VoiceLines.spoken(meters: 1_000) == "1 kilometre")
        #expect(VoiceLines.text(for: .halfway, app: "", remainingMeters: 0, variant: 1).contains(VoiceLines.defaultApp))
        #expect(VoiceLines.text(for: .niceTry(.vehicle), app: "X", remainingMeters: 0, variant: 0) == "Nice try. Cars don't count.")
    }
}

@Suite("Nice try")
struct NiceTryTests {
    private func totals(vehicle: Double = 0, noSteps: Double = 0) -> GateTotals {
        var t = GateTotals()
        t.vehicleMeters = vehicle
        t.noStepsMeters = noSteps
        return t
    }

    @Test("Reports rejected distance once it passes 100 m, then waits two minutes")
    func reportsAndCoolsDown() {
        var detector = NiceTryDetector()
        #expect(detector.check(totals(vehicle: 60), at: 0) == nil)
        #expect(detector.check(totals(vehicle: 140), at: 10) == NiceTryEvent(kind: .vehicle, meters: 140))
        #expect(detector.check(totals(vehicle: 400), at: 60) == nil)
        #expect(detector.check(totals(vehicle: 400), at: 131) == NiceTryEvent(kind: .vehicle, meters: 260))
    }

    @Test("Too-few-steps distance gets its own card")
    func noSteps() {
        var detector = NiceTryDetector()
        #expect(detector.check(totals(noSteps: 150), at: 0) == NiceTryEvent(kind: .noSteps, meters: 150))
    }
}
