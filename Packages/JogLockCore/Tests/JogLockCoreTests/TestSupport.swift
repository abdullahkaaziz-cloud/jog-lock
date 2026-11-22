import Foundation
@testable import JogLockCore

/// Small, seeded random number generator so "random" tests repeat exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Normally distributed value (Box-Muller).
    mutating func gaussian(sigma: Double) -> Double {
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &self)
        let u2 = Double.random(in: 0..<1, using: &self)
        return sigma * (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}

/// GPS position error that wanders slowly, like a real receiver: a
/// Gauss-Markov drift plus a little per-fix jitter. Same model as
/// Tools/simulate.py.
struct WanderingError {
    var sigmaDrift = 2.5
    var tau = 30.0
    var sigmaWhite = 0.6
    private(set) var east = 0.0
    private(set) var north = 0.0

    mutating func step(dt: Double, rng: inout SplitMix64) -> (east: Double, north: Double) {
        let phi = exp(-dt / tau)
        let k = (1 - phi * phi).squareRoot() * sigmaDrift
        east = phi * east + k * rng.gaussian(sigma: 1)
        north = phi * north + k * rng.gaussian(sigma: 1)
        return (east + rng.gaussian(sigma: sigmaWhite), north + rng.gaussian(sigma: sigmaWhite))
    }
}

/// Builds a fix stream for a runner heading due north, one fix per second.
struct TrackBuilder {
    static let metresPerDegreeLat = 111_257.8  // near 51.5° N
    static let metresPerDegreeLon = 69_440.5

    var t: TimeInterval = 1_700_000_000
    var north = 0.0            // metres from the start
    var east = 0.0
    var accuracy = 5.0
    var speedAccuracy = 0.5
    private(set) var fixes: [GPSFix] = []

    mutating func run(seconds: Int, speed: Double) {
        for _ in 0..<seconds {
            t += 1
            north += speed
            fixes.append(fix(offsetEast: 0, offsetNorth: 0, speed: speed, stationary: false))
        }
    }

    mutating func stand(seconds: Int, error: inout WanderingError, rng: inout SplitMix64,
                        reportSpeed: Bool, stationaryFlag: Bool = false) {
        for _ in 0..<seconds {
            t += 1
            let e = error.step(dt: 1, rng: &rng)
            fixes.append(fix(offsetEast: e.east, offsetNorth: e.north,
                             speed: reportSpeed ? 0.1 : -1, stationary: stationaryFlag))
        }
    }

    /// Moves without producing fixes, as if the phone lost GPS.
    mutating func skip(seconds: Int, speed: Double) {
        t += TimeInterval(seconds)
        north += speed * Double(seconds)
    }

    mutating func append(_ fix: GPSFix) {
        fixes.append(fix)
    }

    func fix(offsetEast: Double, offsetNorth: Double, speed: Double, stationary: Bool) -> GPSFix {
        GPSFix(t: t,
               lat: 51.5 + (north + offsetNorth) / Self.metresPerDegreeLat,
               lon: -0.12 + (east + offsetEast) / Self.metresPerDegreeLon,
               hAcc: accuracy,
               speed: speed,
               speedAcc: speed >= 0 ? speedAccuracy : -1,
               stationary: stationary)
    }
}

extension DistanceEngine {
    /// Feeds every fix and returns the decisions, in order.
    @discardableResult
    mutating func process(_ fixes: [GPSFix]) -> [FixDecision] {
        fixes.map { process($0) }
    }
}
