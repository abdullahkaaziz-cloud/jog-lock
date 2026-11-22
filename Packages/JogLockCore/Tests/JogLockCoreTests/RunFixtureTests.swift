import Foundation
import Testing
@testable import JogLockCore

/// The first real jog (22 Nov 2026, Strava 3.00 km), anonymised. The same
/// file and the same expected numbers are used by Tools/test_engine.py, so
/// both implementations are held to one result.
@Suite("Real run fixture")
struct RunFixtureTests {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // JogLockCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // JogLockCore
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Tools/fixtures", isDirectory: true)
    static let fixture = fixtures.appendingPathComponent("run1-anon.jsonl")

    @Test("Replaying the log gives the totals the phone showed")
    func replayMatchesPhone() throws {
        let text = try String(contentsOf: Self.fixture, encoding: .utf8)
        let lines = RunCoding.decodeLines(text)
        let header = try #require(lines.first(where: { $0.type == "header" }))
        let stop = try #require(lines.first(where: { $0.type == "event" && $0.name == "stop" }))

        var engine = DistanceEngine(settings: header.settings ?? .standard)
        for line in lines {
            if let fix = GPSFix(line: line) {
                engine.process(fix)
            }
        }
        let result = engine.finalize()

        #expect(abs(result.cleanMeters - 3012.2215) < 0.01)
        #expect(abs(result.speedMeters - 2863.3921) < 0.01)
        #expect(abs(result.rawMeters - 3048.4658) < 0.01)
        #expect(abs(result.cleanMeters - (stop.clean ?? 0)) < 0.01)
        #expect(abs(result.speedMeters - (stop.speedDist ?? 0)) < 0.01)
        #expect(abs(result.rawMeters - (stop.raw ?? 0)) < 0.01)
    }
}
