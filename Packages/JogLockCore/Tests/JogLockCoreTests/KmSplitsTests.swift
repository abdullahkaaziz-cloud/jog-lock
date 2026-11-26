import Foundation
import Testing
@testable import JogLockCore

@Suite("Last km: how long each whole kilometre took")
struct KmSplitsTests {
    static func near(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-6
    }

    @Test("Steady 6:00 a km gives 6:00 splits")
    func steady() {
        var splits = KmSplits()
        #expect(splits.last == nil)
        splits.add(meters: 500, at: 180)
        #expect(splits.last == nil)
        splits.add(meters: 1_000, at: 360)
        #expect(Self.near(splits.last, 360))
        splits.add(meters: 1_500, at: 540)
        splits.add(meters: 2_100, at: 756)
        #expect(splits.seconds.count == 2)
        #expect(Self.near(splits.last, 360))
    }

    @Test("The moment a kilometre is passed is worked out between two readings")
    func between() {
        var splits = KmSplits()
        splits.add(meters: 1_200, at: 400)
        #expect(Self.near(splits.last, 1_000.0 / 1_200 * 400))
    }

    @Test("Several kilometres in one reading each get a time")
    func several() {
        var splits = KmSplits()
        splits.add(meters: 2_500, at: 750)
        #expect(splits.seconds.count == 2)
        #expect(Self.near(splits.seconds.first, 300))
        #expect(Self.near(splits.last, 300))
    }

    @Test("A distance that goes down or a clock that goes back is ignored")
    func backwards() {
        var splits = KmSplits()
        splits.add(meters: 800, at: 240)
        splits.add(meters: 700, at: 250)
        splits.add(meters: 900, at: 200)
        splits.add(meters: 1_000, at: 300)
        #expect(Self.near(splits.last, 300))
    }

    @Test("A run picked up again doesn't time the kilometre it was part way through")
    func resumed() {
        var splits = KmSplits(resumingAt: 1_500, time: 500)
        splits.add(meters: 2_000, at: 650)
        #expect(splits.last == nil)
        splits.add(meters: 3_000, at: 1_010)
        #expect(Self.near(splits.last, 360))
    }
}
