//
//  DistanceEngine.swift
//  JogLockTracker
//
//  Turns a stream of GPS fixes into a distance, Strava-style: wait for a good
//  signal, drop bad points and jumps, ignore standing still, then add up what
//  is left. Foundation only, so the logic can be replayed off the phone.
//
//  Tools/replay.py is a line-for-line mirror of this file. If you change the
//  rules here, change them there too (the replay prints a parity check).
//

import Foundation

/// One location fix, reduced to what the engine needs.
struct GPSFix: Equatable {
    var t: TimeInterval     // seconds since 1970
    var lat: Double
    var lon: Double
    var hAcc: Double        // metres; negative means invalid
    var speed: Double       // m/s; negative means invalid
    var speedAcc: Double    // m/s; negative means invalid
    var stationary: Bool    // iOS says the device is not moving
}

/// Tuning knobs. Defaults are a starting point; tune them with logged runs.
struct EngineSettings: Codable, Equatable {
    var warmupAccuracy: Double = 15         // m: a fix this good counts toward warm-up
    var warmupFixes: Int = 3                // consecutive good fixes before counting starts
    var maxAccuracy: Double = 25            // m: worse fixes are ignored while tracking
    var maxSpeed: Double = 9                // m/s: faster implied movement is a GPS jump
    var stopSpeed: Double = 0.5             // m/s: slower means standing still
    var minStepFloor: Double = 5            // m: minimum move before a segment counts
    var minStepAccuracyFactor: Double = 0.5 // min step is also at least this x accuracy
    var maxGap: Double = 120                // s: longer gaps while moving are not bridged
    var jumpResetCount: Int = 3             // consecutive jumps before re-anchoring
    var speedMaxAccuracy: Double = 3        // m/s: worse speed readings are ignored
    var speedMaxDt: Double = 10             // s: longer intervals use straight-line distance
    var resumeGap: Double = 5               // s: an update pause this long while stationary = iOS paused

    static let standard = EngineSettings()
}

/// What the engine did with a fix. Raw values are written to the log.
enum FixDecision: String, Codable {
    case warmingUp
    case warmupComplete
    case accepted
    case pending
    case stationary
    case drift
    case rejectedInvalid
    case rejectedOutOfOrder
    case rejectedLowAccuracy
    case rejectedJump
    case jumpReset
    case gapReset
}

enum EnginePhase: String, Codable {
    case warmingUp
    case tracking
}

/// Everything the UI and the summary need.
struct EngineSnapshot: Equatable {
    var phase: EnginePhase = .warmingUp
    var cleanMeters: Double = 0     // main number: Strava-style cleaned distance
    var speedMeters: Double = 0     // comparison: sum of GPS speed x time
    var rawMeters: Double = 0       // comparison: every fix joined up, no clean-up
    var movingSeconds: Double = 0
    var fixCount: Int = 0
    var acceptedCount: Int = 0
    var rejected: [String: Int] = [:]
    var isPaused: Bool = false
}

enum Geo {
    private static let a = 6_378_137.0
    private static let flattening = 1.0 / 298.257223563
    private static let e2 = flattening * (2.0 - flattening)
    private static let degToRad = Double.pi / 180.0

    /// Distance in metres between two nearby points, using the WGS84
    /// radii at the mid latitude (more accurate than a spherical haversine
    /// for the short hops between fixes).
    static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi = ((lat1 + lat2) / 2) * degToRad
        let s = sin(phi)
        let w = (1 - e2 * s * s).squareRoot()
        let n = a / w
        let m = a * (1 - e2) / (w * w * w)
        let dLat = (lat2 - lat1) * degToRad
        var dLon = (lon2 - lon1) * degToRad
        if dLon > Double.pi {
            dLon -= 2 * Double.pi
        } else if dLon < -Double.pi {
            dLon += 2 * Double.pi
        }
        let dy = dLat * m
        let dx = dLon * n * cos(phi)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func distance(_ p: GPSFix, _ q: GPSFix) -> Double {
        distance(lat1: p.lat, lon1: p.lon, lat2: q.lat, lon2: q.lon)
    }
}

struct DistanceEngine {
    let settings: EngineSettings
    private(set) var snapshot = EngineSnapshot()

    private var goodStreak = 0
    private var anchor: GPSFix?
    private var lastSeen: GPSFix?
    private var lastGood: GPSFix?
    private var rawLast: GPSFix?
    private var speedLast: GPSFix?
    private var jumpStreak = 0
    private var motionStart: TimeInterval = -Double.infinity

    init(settings: EngineSettings = .standard) {
        self.settings = settings
    }

    @discardableResult
    mutating func process(_ f: GPSFix) -> FixDecision {
        let s = settings
        snapshot.fixCount += 1

        // Raw estimator: every fix with a valid accuracy, from the first one.
        if f.hAcc >= 0 {
            if let p = rawLast, f.t > p.t {
                snapshot.rawMeters += Geo.distance(p, f)
            }
            if rawLast == nil || f.t > rawLast!.t {
                rawLast = f
            }
        }

        if snapshot.phase == .warmingUp {
            if f.hAcc >= 0 && f.hAcc <= s.warmupAccuracy {
                goodStreak += 1
            } else {
                goodStreak = 0
            }
            if goodStreak >= s.warmupFixes {
                snapshot.phase = .tracking
                anchor = f
                lastSeen = f
                lastGood = f
                speedLast = f
                return .warmupComplete
            }
            return .warmingUp
        }

        if f.hAcc < 0 {
            return reject(.rejectedInvalid)
        }
        if let seen = lastSeen, f.t <= seen.t {
            return reject(.rejectedOutOfOrder)
        }
        let sincePrev = lastSeen.map { f.t - $0.t } ?? 0
        lastSeen = f
        if snapshot.isPaused && sincePrev > s.resumeGap {
            // iOS paused updates while we stood still and has just resumed:
            // assume movement began about a second before this fix.
            motionStart = f.t - 1.0
        }

        updateSpeedEstimate(f)

        if f.hAcc > s.maxAccuracy {
            return reject(.rejectedLowAccuracy)
        }

        guard let a = anchor else {
            // Defensive: tracking always has an anchor.
            anchor = f
            lastGood = f
            return .pending
        }

        let dt = f.t - a.t
        let d = Geo.distance(a, f)

        if dt > s.maxGap && !snapshot.isPaused {
            anchor = f
            lastGood = f
            jumpStreak = 0
            return .gapReset
        }

        if dt > 0 && d / dt > s.maxSpeed {
            jumpStreak += 1
            if jumpStreak >= s.jumpResetCount {
                anchor = f
                lastGood = f
                jumpStreak = 0
                return .jumpReset
            }
            return reject(.rejectedJump)
        }
        jumpStreak = 0
        lastGood = f

        let minStep = max(s.minStepFloor, s.minStepAccuracyFactor * max(a.hAcc, f.hAcc))
        let slow = f.speed >= 0 && f.speed < s.stopSpeed && d < 2 * minStep
        if f.stationary || slow {
            anchor = f  // drag the anchor so standing still never adds distance
            snapshot.isPaused = true
            return .stationary
        }
        snapshot.isPaused = false

        if d >= minStep {
            // If it took too long to get this far, it is GPS drift around a
            // standing runner, not movement.
            let dtMove = f.t - max(a.t, motionStart)
            if dtMove > 0 && d / dtMove < s.stopSpeed {
                anchor = f
                snapshot.isPaused = true
                return .drift
            }
            snapshot.cleanMeters += d
            snapshot.movingSeconds += dtMove
            snapshot.acceptedCount += 1
            anchor = f
            return .accepted
        }
        return .pending
    }

    /// Counts the last partial segment when the run ends.
    @discardableResult
    mutating func finalize() -> EngineSnapshot {
        let s = settings
        guard snapshot.phase == .tracking, !snapshot.isPaused,
              let a = anchor, let g = lastGood, g.t > a.t else {
            return snapshot
        }
        let dt = g.t - a.t
        let d = Geo.distance(a, g)
        if dt <= s.maxGap && d / dt <= s.maxSpeed {
            snapshot.cleanMeters += d
            snapshot.movingSeconds += max(0, g.t - max(a.t, motionStart))
            anchor = g
        }
        return snapshot
    }

    // MARK: - Private

    private mutating func reject(_ reason: FixDecision) -> FixDecision {
        snapshot.rejected[reason.rawValue, default: 0] += 1
        return reason
    }

    private func speedUsable(_ x: GPSFix) -> Bool {
        let s = settings
        return x.speed >= 0
            && x.speedAcc >= 0 && x.speedAcc <= s.speedMaxAccuracy
            && x.hAcc >= 0 && x.hAcc <= s.maxAccuracy
    }

    private mutating func updateSpeedEstimate(_ f: GPSFix) {
        let s = settings
        let previous = speedLast
        speedLast = f
        guard let p = previous else { return }
        let dt = f.t - p.t
        guard dt > 0, !f.stationary else { return }
        if dt <= s.speedMaxDt {
            if speedUsable(p) && speedUsable(f) {
                let v = (p.speed + f.speed) / 2
                if v >= s.stopSpeed && v <= s.maxSpeed {
                    snapshot.speedMeters += v * dt
                }
            }
            return
        }
        // Long interval: fall back to the straight line if it is plausible.
        if dt <= s.maxGap,
           p.hAcc >= 0, p.hAcc <= s.maxAccuracy,
           f.hAcc >= 0, f.hAcc <= s.maxAccuracy {
            let d = Geo.distance(p, f)
            if d / dt <= s.maxSpeed {
                snapshot.speedMeters += d
            }
        }
    }
}
