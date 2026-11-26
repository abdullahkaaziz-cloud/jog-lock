//
//  TrackGeometry.swift
//  JogLockCore
//
//  The running track Jog Lock draws progress round: a stadium seen from above.
//

import Foundation

/// One piece of the track's line.
public enum TrackSegment: Equatable, Sendable {
    /// A straight from one point to another.
    case line(fromX: Double, fromY: Double, toX: Double, toY: Double)
    /// A circular arc. Angles are in radians, measured from +x towards +y
    /// (down on screen), so a positive sweep goes clockwise on screen.
    case arc(centerX: Double, centerY: Double, radius: Double, startAngle: Double, sweep: Double)

    /// The length along the line.
    public var length: Double {
        switch self {
        case let .line(fromX, fromY, toX, toY):
            return hypot(toX - fromX, toY - fromY)
        case let .arc(_, _, radius, _, sweep):
            return abs(sweep) * radius
        }
    }

    /// The point `distance` along the segment, clamped to its ends.
    public func point(at distance: Double) -> (x: Double, y: Double) {
        let length = self.length
        let t = length > 0 ? min(max(distance / length, 0), 1) : 0
        switch self {
        case let .line(fromX, fromY, toX, toY):
            return (fromX + (toX - fromX) * t, fromY + (toY - fromY) * t)
        case let .arc(centerX, centerY, radius, startAngle, sweep):
            let angle = startAngle + sweep * t
            return (centerX + radius * cos(angle), centerY + radius * sin(angle))
        }
    }
}

/// A stadium in a `width` × `height` box: two straights joined by half circles.
///
/// The line starts at the start/finish line and goes clockwise on screen
/// (y down). Lying down (wider than tall) it starts at the left end of the
/// top straight; standing up it starts at the top, in the middle.
public struct TrackGeometry: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    /// Taller than wide: the track stands up.
    public var isStanding: Bool { height > width }

    /// The radius of the curved ends.
    public var radius: Double { min(width, height) / 2 }

    /// The length of each straight.
    public var straight: Double { abs(width - height) }

    /// The whole way round.
    public var perimeter: Double { 2 * straight + 2 * Double.pi * radius }

    /// The start/finish line.
    public var start: (x: Double, y: Double) {
        segments.first.map { $0.point(at: 0) } ?? (0, 0)
    }

    /// The line, as segments in running order.
    public var segments: [TrackSegment] {
        let r = radius
        let s = straight
        guard r > 0 else { return [] }
        let half = Double.pi / 2
        if isStanding {
            return [
                .arc(centerX: r, centerY: r, radius: r, startAngle: -half, sweep: half),
                .line(fromX: 2 * r, fromY: r, toX: 2 * r, toY: r + s),
                .arc(centerX: r, centerY: r + s, radius: r, startAngle: 0, sweep: .pi),
                .line(fromX: 0, fromY: r + s, toX: 0, toY: r),
                .arc(centerX: r, centerY: r, radius: r, startAngle: .pi, sweep: half),
            ]
        }
        return [
            .line(fromX: r, fromY: 0, toX: r + s, toY: 0),
            .arc(centerX: r + s, centerY: r, radius: r, startAngle: -half, sweep: .pi),
            .line(fromX: r + s, fromY: 2 * r, toX: r, toY: 2 * r),
            .arc(centerX: r, centerY: r, radius: r, startAngle: half, sweep: .pi),
        ]
    }

    /// The point a fraction of the way round from the start/finish line.
    /// Fractions outside 0...1 wrap, so 1.25 is a quarter into a second lap.
    public func point(at fraction: Double) -> (x: Double, y: Double) {
        let pieces = segments
        guard !pieces.isEmpty, fraction.isFinite else { return (0, 0) }
        var wrapped = fraction.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        if fraction > 0, wrapped == 0 { wrapped = 1 }
        var remaining = wrapped * perimeter
        for piece in pieces {
            let length = piece.length
            if remaining <= length { return piece.point(at: remaining) }
            remaining -= length
        }
        return pieces[pieces.count - 1].point(at: pieces[pieces.count - 1].length)
    }
}
