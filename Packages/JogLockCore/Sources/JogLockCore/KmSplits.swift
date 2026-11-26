//
//  KmSplits.swift
//  JogLockCore
//
//  How long each whole kilometre of a run took, for "last km" on the run
//  screen. It's given the run's counted distance as it grows, against a
//  clock that leaves out stops: GPS moving time outdoors, time since the
//  start on a treadmill.
//

import Foundation

public struct KmSplits: Equatable, Sendable {
    /// Seconds each whole kilometre took, in order.
    public private(set) var seconds: [Double] = []
    private var meters: Double
    private var time: Double
    /// When the last whole kilometre was passed. Nil after picking a run up
    /// part way through a kilometre, until the next one is passed.
    private var mark: Double?

    /// A run from its start.
    public init() {
        meters = 0
        time = 0
        mark = 0
    }

    /// A run picked up again at `meters` and `time`, after iOS stopped the
    /// app. The kilometre it's part way through isn't timed.
    public init(resumingAt meters: Double, time: Double) {
        self.meters = meters
        self.time = time
        mark = nil
    }

    /// The last whole kilometre's time.
    public var last: Double? {
        seconds.last
    }

    /// The distance so far, at `newTime` on the clock. A distance that went
    /// down, or a clock that went back, is ignored.
    public mutating func add(meters newMeters: Double, at newTime: Double) {
        guard newMeters > meters, newTime >= time else { return }
        var boundary = (meters / 1_000).rounded(.down) * 1_000 + 1_000
        while boundary <= newMeters {
            let passed = time + (boundary - meters) / (newMeters - meters) * (newTime - time)
            if let mark {
                seconds.append(passed - mark)
            }
            mark = passed
            boundary += 1_000
        }
        meters = newMeters
        time = newTime
    }
}
