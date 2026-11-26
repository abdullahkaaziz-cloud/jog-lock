//
//  RunActivityAttributes.swift
//  Shared between the app and the JogLockWidgets extension.
//
//  The lock-screen and Dynamic Island countdown during a run.
//

import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var meters: Double          // live distance: counted plus still being checked
        var targetMeters: Double
        var unlocked: Bool
        var paused: Bool

        var remainingMeters: Double {
            max(0, targetMeters - meters)
        }

        var progress: Double {
            targetMeters > 0 ? min(1, meters / targetMeters) : 0
        }
    }

    var app: String                 // the app they're running for
    var startedAt: Date
}

extension RunActivityAttributes.ContentState {
    /// "1.8 km" or "750 m".
    var remainingText: String {
        let m = remainingMeters
        if m >= 1_000 {
            return String(format: "%.1f km", m / 1_000)
        }
        return "\(Int((m / 10).rounded()) * 10) m"
    }
}
