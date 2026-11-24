import Foundation
import Testing
@testable import JogLockCore

@Suite("The run reel")
struct ReelTests {
    @Test("Ten seconds at 30 frames a second")
    func frames() {
        #expect(ReelTimeline.frames == Int(ReelTimeline.seconds) * ReelTimeline.fps)
        #expect(ReelTimeline.time(ofFrame: 150) == 5)
    }

    @Test("The route and the counter finish together, eased")
    func drawing() {
        #expect(ReelTimeline.drawn(at: 0) == 0)
        #expect(ReelTimeline.drawn(at: 3) == 0.5)
        #expect(ReelTimeline.drawn(at: 6) == 1)
        #expect(ReelTimeline.drawn(at: 9) == 1)
        #expect(ReelTimeline.drawn(at: 1) < 1.0 / 6)
        let timeline = ReelTimeline(meters: 3_200)
        #expect(timeline.shownMeters(at: 6) == 3_200)
        #expect(timeline.shownMeters(at: 0) == 0)
    }

    @Test("The lock shakes, then springs open, then the line fades in")
    func lock() {
        #expect(ReelTimeline.shake(at: 5.9) == 0)
        #expect(abs(ReelTimeline.shake(at: 6.02)) > 1)
        #expect(ReelTimeline.shake(at: 7.2) == 0)
        #expect(ReelTimeline.open(at: 7.2) == 0)
        #expect(abs(ReelTimeline.open(at: 7.4) - 0.5) < 1e-9)
        #expect(ReelTimeline.open(at: 8) == 1)
        #expect(ReelTimeline.titleOpacity(at: 7.6) == 0)
        #expect(ReelTimeline.titleOpacity(at: 8.5) == 1)
    }

    @Test("The part of the route drawn so far, by length")
    func partialRoute() {
        let square = [[Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 10, y: 10)]]
        #expect(ReelRoute.partial(square, share: 0.75) == [[Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 10, y: 5)]])
        #expect(ReelRoute.partial(square, share: 0).isEmpty)
        #expect(ReelRoute.partial(square, share: 1) == square)
        let two = [[Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)], [Point2D(x: 20, y: 0), Point2D(x: 30, y: 0)]]
        #expect(ReelRoute.partial(two, share: 0.5) == [[Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)]])
        #expect(ReelRoute.partial(two, share: 0.75).count == 2)
        #expect(ReelRoute.partial([], share: 1).isEmpty)
    }
}
