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
}
