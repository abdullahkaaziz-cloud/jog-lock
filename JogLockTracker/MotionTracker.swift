//
//  MotionTracker.swift
//  JogLockTracker
//
//  Steps and activity from the iPhone's motion coprocessor, for the step
//  check. Needs Motion & Fitness permission (NSMotionUsageDescription).
//

import CoreMotion
import Foundation
import JogLockCore

struct PedometerTotals: Sendable {
    var steps: Int
    var meters: Double?
}

@MainActor
final class MotionTracker {
    /// Called on the main actor with each pedometer update: the step count
    /// since the run started, the iPhone's own distance estimate (m) and the
    /// current cadence (steps per second), when it has them.
    var onSteps: ((StepSample, Double?, Double?) -> Void)?
    /// Called on the main actor with each new activity.
    var onMotion: ((MotionSample) -> Void)?

    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()

    static var canCountSteps: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    static var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Starts updates. Step counts are cumulative from `date`, so after a
    /// relaunch the first update includes steps taken while the app was gone.
    func start(from date: Date) {
        stop()
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: date) { [weak self] data, _ in
                guard let data else { return }
                let sample = StepSample(t: data.endDate.timeIntervalSince1970, steps: data.numberOfSteps.intValue)
                let meters = data.distance?.doubleValue
                let cadence = data.currentCadence?.doubleValue
                Task { @MainActor in
                    self?.onSteps?(sample, meters, cadence)
                }
            }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
                guard let activity else { return }
                let sample = MotionSample(activity)
                Task { @MainActor in
                    self?.onMotion?(sample)
                }
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
    }

    /// The step count and distance between two times, from the motion
    /// coprocessor's history (it keeps the last 7 days).
    func totals(from start: Date, to end: Date) async -> PedometerTotals? {
        guard CMPedometer.isStepCountingAvailable(), end > start else { return nil }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                let totals = data.map { PedometerTotals(steps: $0.numberOfSteps.intValue, meters: $0.distance?.doubleValue) }
                continuation.resume(returning: totals)
            }
        }
    }

    /// Core Motion's activities between two times (it keeps the last 7 days).
    func activities(from start: Date, to end: Date) async -> [MotionSample] {
        guard CMMotionActivityManager.isActivityAvailable(), end > start else { return [] }
        return await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: start, to: end, to: OperationQueue.main) { activities, _ in
                continuation.resume(returning: (activities ?? []).map(MotionSample.init))
            }
        }
    }
}

extension MotionSample {
    init(_ activity: CMMotionActivity) {
        let kind: MotionKind
        if activity.automotive {
            kind = .automotive
        } else if activity.cycling {
            kind = .cycling
        } else if activity.running {
            kind = .running
        } else if activity.walking {
            kind = .walking
        } else if activity.stationary {
            kind = .stationary
        } else {
            kind = .unknown
        }
        let confidence: MotionConfidence
        switch activity.confidence {
        case .high:
            confidence = .high
        case .medium:
            confidence = .medium
        default:
            confidence = .low
        }
        self.init(start: activity.startDate.timeIntervalSince1970, kind: kind, confidence: confidence)
    }
}
