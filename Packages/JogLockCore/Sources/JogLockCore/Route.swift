//
//  Route.swift
//  JogLockCore
//
//  The path a run took, for maps and share cards: the points the engine
//  counted, split where counting restarted (warm-up, GPS gap, jump).
//

import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// A point on a drawing surface (x to the right, y down).
public struct Point2D: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Builds a route as fixes arrive, the same way GPX's "counted points" track does.
public struct RouteBuilder: Sendable {
    public private(set) var segments: [[Coordinate]] = []

    public init() {}

    public mutating func add(_ coordinate: Coordinate, decision: FixDecision) {
        switch decision {
        case .warmupComplete, .gapReset, .jumpReset:
            segments.append([coordinate])
        case .accepted:
            if segments.isEmpty {
                segments.append([coordinate])
            } else {
                segments[segments.count - 1].append(coordinate)
            }
        default:
            break
        }
    }
}

public enum Route {
    /// The counted route of a logged run.
    public static func segments(from lines: [LogLine]) -> [[Coordinate]] {
        var builder = RouteBuilder()
        for line in lines where line.type == "fix" {
            guard let lat = line.lat, let lon = line.lon,
                  let raw = line.decision, let decision = FixDecision(rawValue: raw) else { continue }
            builder.add(Coordinate(lat: lat, lon: lon), decision: decision)
        }
        return builder.segments.filter { !$0.isEmpty }
    }

    /// Fits a route into a width x height box for drawing, north up, keeping
    /// its proportions and leaving `padding` on every side.
    public static func project(_ segments: [[Coordinate]], width: Double, height: Double,
                               padding: Double = 0) -> [[Point2D]] {
        let all = segments.flatMap { $0 }
        guard let first = all.first else { return [] }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for c in all {
            minLat = min(minLat, c.lat)
            maxLat = max(maxLat, c.lat)
            minLon = min(minLon, c.lon)
            maxLon = max(maxLon, c.lon)
        }
        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2
        let lonScale = cos(midLat * .pi / 180)
        let spanX = (maxLon - minLon) * lonScale
        let spanY = maxLat - minLat
        let boxW = max(width - 2 * padding, 0)
        let boxH = max(height - 2 * padding, 0)
        let span = max(spanX / max(boxW, 1e-9), spanY / max(boxH, 1e-9))
        let scale = span > 0 ? 1 / span : 0
        return segments.map { segment in
            segment.map { c in
                Point2D(x: width / 2 + (c.lon - midLon) * lonScale * scale,
                        y: height / 2 - (c.lat - midLat) * scale)
            }
        }
    }
}
