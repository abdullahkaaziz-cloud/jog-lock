import Foundation
import Testing
@testable import JogLockCore

@Suite("Format")
struct FormatTests {
    @Test("Kilometres have two decimals")
    func km() {
        #expect(Format.km(3.0122) == "3.01")
        #expect(Format.km(0) == "0.00")
    }

    @Test("Short distances read like a label: 1.8 km, 2 km, 750 m")
    func shortDistance() {
        #expect(Format.shortDistance(1_800) == "1.8 km")
        #expect(Format.shortDistance(2_000) == "2 km")
        #expect(Format.shortDistance(1_049) == "1 km")
        #expect(Format.shortDistance(950) == "1 km")
        #expect(Format.shortDistance(944) == "940 m")
        #expect(Format.shortDistance(3) == "10 m")
        #expect(Format.shortDistance(-5) == "10 m")
    }

    @Test("Durations are m:ss, or h:mm:ss from an hour")
    func duration() {
        #expect(Format.duration(0) == "0:00")
        #expect(Format.duration(65.4) == "1:05")
        #expect(Format.duration(3_725) == "1:02:05")
        #expect(Format.duration(-1) == "--")
        #expect(Format.duration(.infinity) == "--")
    }

    @Test("Rejection reasons read as plain words")
    func reason() {
        #expect(Format.reason(FixDecision.rejectedLowAccuracy.rawValue) == "weak signal")
        #expect(Format.reason(FixDecision.rejectedJump.rawValue) == "jumps")
        #expect(Format.reason("somethingNew") == "somethingNew")
    }

    @Test("Differences are signed percentages")
    func percent() {
        #expect(Format.percent(3_012, versus: 3_000) == "+0.4%")
        #expect(Format.percent(2_863, versus: 3_000) == "-4.6%")
        #expect(Format.percent(1, versus: 0) == "")
    }

    @Test("A difference too small to show is +0.0%, never -0.0%")
    func percentNegativeZero() {
        #expect(Format.percent(2_999.999, versus: 3_000) == "+0.0%")
        #expect(Format.percent(3_000.001, versus: 3_000) == "+0.0%")
    }

    @Test("The Time tile keeps a finished run's length instead of going back to 0:00")
    func elapsed() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let run = RunSummary(id: "run-a", startedAt: start, endedAt: start.addingTimeInterval(1_260),
                             targetKm: 2.5, cleanMeters: 3_012, speedMeters: 2_863, rawMeters: 3_048,
                             movingSeconds: 1_243, fixCount: 1_264, acceptedCount: 512, rejected: [:],
                             device: "iPhone17,5", os: "27.0", appVersion: "0.1 (1)", settings: .standard)
        let later = start.addingTimeInterval(5_000)
        #expect(Format.elapsed(now: later, activeSince: nil, lastRun: run) == "21:00")
        #expect(Format.elapsed(now: start.addingTimeInterval(90), activeSince: start, lastRun: run) == "1:30")
        #expect(Format.elapsed(now: later, activeSince: nil, lastRun: nil) == "0:00")
    }
}
