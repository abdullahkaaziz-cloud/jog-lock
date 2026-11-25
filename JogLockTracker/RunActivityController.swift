//
//  RunActivityController.swift
//  JogLockTracker
//
//  Starts, updates and ends the lock-screen countdown (Live Activity).
//  Updates are throttled: every 20 m or 15 s, or when the state changes.
//

import ActivityKit
import Foundation

@MainActor
final class RunActivityController {
    private var activity: Activity<RunActivityAttributes>?
    private var lastSent: RunActivityAttributes.ContentState?
    private var lastSentAt = Date.distantPast

    func start(app: String, startedAt: Date, targetMeters: Double) {
        end(final: nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RunActivityAttributes.ContentState(meters: 0, targetMeters: targetMeters,
                                                      unlocked: false, paused: false)
        activity = try? Activity.request(attributes: RunActivityAttributes(app: app, startedAt: startedAt),
                                         content: ActivityContent(state: state, staleDate: nil),
                                         pushType: nil)
        lastSent = state
        lastSentAt = Date()
    }

    /// Picks up the activity of a run that iOS interrupted.
    func reattach() {
        activity = Activity<RunActivityAttributes>.activities.first
    }

    func update(meters: Double, targetMeters: Double, unlocked: Bool, paused: Bool) {
        guard let activity else { return }
        let state = RunActivityAttributes.ContentState(meters: meters, targetMeters: targetMeters,
                                                      unlocked: unlocked, paused: paused)
        if let last = lastSent, last.unlocked == unlocked, last.paused == paused,
           abs(last.meters - meters) < 20, Date().timeIntervalSince(lastSentAt) < 15 {
            return
        }
        lastSent = state
        lastSentAt = Date()
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Ends the countdown, leaving the final state on the lock screen for 15 minutes.
    func end(final state: RunActivityAttributes.ContentState?) {
        guard let activity else { return }
        self.activity = nil
        lastSent = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        Task {
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
        }
    }
}
