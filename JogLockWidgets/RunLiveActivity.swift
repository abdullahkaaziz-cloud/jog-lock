//
//  RunLiveActivity.swift
//  JogLockWidgets
//
//  "0.8 km to TikTok" on the lock screen and in the Dynamic Island while
//  a run is going.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRunView(app: context.attributes.app,
                              startedAt: context.attributes.startedAt,
                              state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.unlocked ? "Unlocked" : context.state.remainingText,
                          systemImage: context.state.unlocked ? "lock.open.fill" : "figure.run")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 70)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .tint(.green)
                        Text(headline(app: context.attributes.app, state: context.state))
                            .font(.subheadline)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.unlocked ? "lock.open.fill" : "figure.run")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.unlocked ? "Done" : context.state.remainingText)
                    .monospacedDigit()
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: context.state.unlocked ? "lock.open.fill" : "figure.run")
                    .foregroundStyle(.green)
            }
        }
    }
}

private func headline(app: String, state: RunActivityAttributes.ContentState) -> String {
    if state.unlocked {
        return "\(app) is unlocked"
    }
    if state.paused {
        return "Paused · \(state.remainingText) to \(app)"
    }
    return "\(state.remainingText) to \(app)"
}

struct LockScreenRunView: View {
    let app: String
    let startedAt: Date
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: state.unlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(.green)
                Text(headline(app: app, state: state))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(startedAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            ProgressView(value: state.progress)
                .tint(.green)
            Text(String(format: "%.2f of %.2f km", state.meters / 1_000, state.targetMeters / 1_000))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
    }
}
