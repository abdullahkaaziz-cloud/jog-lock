import Foundation
import Testing
@testable import JogLockCore

@Suite("The track drawn on Today and during a run")
struct TrackGeometryTests {
    /// The progress line on Today: 296 × 176, as on the design canvas.
    static let lying = TrackGeometry(width: 296, height: 176)
    /// The progress line during a run: 296 × 416.
    static let standing = TrackGeometry(width: 296, height: 416)

    static func near(_ point: (x: Double, y: Double), _ x: Double, _ y: Double, within tolerance: Double = 0.5) -> Bool {
        abs(point.x - x) <= tolerance && abs(point.y - y) <= tolerance
    }

    @Test("A lying track starts at the left end of the top straight")
    func lyingStart() {
        let track = Self.lying
        #expect(!track.isStanding)
        #expect(track.radius == 88)
        #expect(track.straight == 120)
        #expect(Self.near(track.start, 88, 0))
        #expect(abs(track.perimeter - (240 + 2 * Double.pi * 88)) < 1e-9)
    }

    @Test("Going clockwise: along the top, round the right end, back along the bottom")
    func lyingClockwise() {
        let track = Self.lying
        let p = track.perimeter
        #expect(Self.near(track.point(at: 120 / p), 208, 0))                       // end of the top straight
        #expect(Self.near(track.point(at: (120 + .pi * 88 / 2) / p), 296, 88))     // the far right
        #expect(Self.near(track.point(at: (120 + .pi * 88) / p), 208, 176))        // start of the bottom straight
        #expect(Self.near(track.point(at: (240 + .pi * 88) / p), 88, 176))         // end of the bottom straight
        #expect(Self.near(track.point(at: (240 + .pi * 88 * 1.5) / p), 0, 88))     // the far left
    }

    @Test("40% round sits where the design puts the runner")
    func designRunner() {
        // On the canvas the line is inset 27 points, and the runner at 40% is at (304, 170).
        #expect(Self.near(Self.lying.point(at: 0.4), 304 - 27, 170 - 27, within: 1.5))
    }

    @Test("A standing track starts at the top, in the middle")
    func standingStart() {
        let track = Self.standing
        #expect(track.isStanding)
        #expect(track.radius == 148)
        #expect(track.straight == 120)
        #expect(Self.near(track.start, 148, 0))
        let p = track.perimeter
        #expect(Self.near(track.point(at: (.pi * 148 / 2) / p), 296, 148))                // round to the right
        #expect(Self.near(track.point(at: (.pi * 148 / 2 + 120) / p), 296, 268))          // down the right straight
        #expect(Self.near(track.point(at: (.pi * 148 * 1.5 + 120) / p), 0, 268))          // round the bottom
        #expect(Self.near(track.point(at: (.pi * 148 * 1.5 + 240) / p), 0, 148))          // up the left straight
    }

    @Test("Fractions wrap round the track")
    func wraps() {
        let track = Self.lying
        #expect(Self.near(track.point(at: 1.25), track.point(at: 0.25).x, track.point(at: 0.25).y))
        #expect(Self.near(track.point(at: -0.25), track.point(at: 0.75).x, track.point(at: 0.75).y))
        #expect(Self.near(track.point(at: 1), 88, 0))
        #expect(Self.near(track.point(at: 0), 88, 0))
    }

    @Test("The segments add up to the perimeter")
    func segmentsAddUp() {
        for track in [Self.lying, Self.standing, TrackGeometry(width: 100, height: 100)] {
            let total = track.segments.reduce(0) { $0 + $1.length }
            #expect(abs(total - track.perimeter) < 1e-9)
        }
    }

    @Test("An empty box draws nothing and does not crash")
    func empty() {
        let track = TrackGeometry(width: 0, height: 120)
        #expect(track.segments.isEmpty)
        #expect(Self.near(track.point(at: 0.5), 0, 0))
        #expect(Self.near(TrackGeometry(width: 10, height: 10).point(at: .nan), 0, 0))
    }
}
