//
//  Reel.swift
//  JogLockCore
//
//  The 10-second story video of a run: the route draws itself while the
//  kilometres tick up, the lock shakes and springs open, then "TikTok
//  unlocked". This is its timing and the part of the route drawn so far;
//  the app draws the frames.
//

import Foundation

public struct ReelTimeline: Sendable {
    public static let seconds = 10.0
    public static let fps = 30
    public static let frames = 300
    /// When the route has finished drawing.
    public static let drawEnds = 6.0
    /// When the lock stops shaking and starts to open.
    public static let shakeEnds = 7.2
    /// When the lock is fully open.
    public static let openEnds = 7.6

    public let meters: Double

    public init(meters: Double) {
        self.meters = meters
    }

    public static func time(ofFrame frame: Int) -> Double {
        Double(frame) / Double(fps)
    }

    /// Share of the route drawn: eased in and out over the first six seconds.
    public static func drawn(at t: Double) -> Double {
        let x = min(1, max(0, t / drawEnds))
        return x * x * (3 - 2 * x)
    }

    /// The counter's distance, keeping pace with the route.
    public func shownMeters(at t: Double) -> Double {
        meters * Self.drawn(at: t)
    }

    /// The lock's tilt in degrees: a shake that dies away once the route's drawn.
    public static func shake(at t: Double) -> Double {
        guard t >= drawEnds, t < shakeEnds else { return 0 }
        let local = t - drawEnds
        let fade = 1 - local / (shakeEnds - drawEnds)
        return 14 * sin(local * 2 * .pi * 6) * fade
    }

    /// How open the lock is: 0 shut, 1 open.
    public static func open(at t: Double) -> Double {
        min(1, max(0, (t - shakeEnds) / (openEnds - shakeEnds)))
    }

    /// The closing line fades in once the lock is open.
    public static func titleOpacity(at t: Double) -> Double {
        min(1, max(0, (t - openEnds) / 0.6))
    }
}

public enum ReelRoute {
    /// The first `share` of the route by length: whole segments, then the
    /// part of the one it ends in.
    public static func partial(_ segments: [[Point2D]], share: Double) -> [[Point2D]] {
        let total = segments.map(length).reduce(0, +)
        guard total > 0 else { return share >= 1 ? segments : [] }
        var left = total * min(1, max(0, share))
        var result: [[Point2D]] = []
        for segment in segments {
            guard left > 0, let first = segment.first else { break }
            var drawn = [first]
            for (from, to) in zip(segment, segment.dropFirst()) {
                let step = distance(from, to)
                if step <= left {
                    drawn.append(to)
                    left -= step
                } else {
                    let part = left / step
                    drawn.append(Point2D(x: from.x + (to.x - from.x) * part, y: from.y + (to.y - from.y) * part))
                    left = 0
                    break
                }
            }
            result.append(drawn)
        }
        return result
    }

    static func length(_ segment: [Point2D]) -> Double {
        zip(segment, segment.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func distance(_ from: Point2D, _ to: Point2D) -> Double {
        ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y)).squareRoot()
    }
}
