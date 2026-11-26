//
//  RunLiveActivity.swift
//  JogLockWidgets
//
//  "0.57 KM TO TIKTOK" on the lock screen and in the Dynamic Island while a
//  run is going: a paper card with the distance left and the run as a red
//  lane filling with ink, and a red dot for running in the island.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenRunView(app: context.attributes.app, startedAt: context.attributes.startedAt,
                              state: context.state)
                .activityBackgroundTint(JL.paper)
                .activitySystemActionForegroundColor(JL.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        StatusDot(state: context.state)
                        Text(status(context.state))
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.subheadline)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .opacity(0.7)
                        .frame(maxWidth: 72, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Headline(app: context.attributes.app, state: context.state, size: 34)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(JL.redOnInk)
                                        .frame(width: proxy.size.width * context.state.progress)
                                }
                        }
                        .frame(height: 6)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                StatusDot(state: context.state)
            } compactTrailing: {
                Text(context.state.unlocked ? "Open" : context.state.remainingText)
                    .font(.jlHeading(14))
                    .monospacedDigit()
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: context.state.progress)
                        .stroke(JL.redOnInk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(2)
            }
            .keylineTint(JL.redOnInk)
        }
    }
}

private func status(_ state: RunActivityAttributes.ContentState) -> String {
    if state.unlocked {
        return "Unlocked"
    }
    return state.paused ? "Paused" : "Running"
}

/// Red for running, grey when paused, the open lock once unlocked.
private struct StatusDot: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        if state.unlocked {
            Image(systemName: "lock.open.fill")
                .foregroundStyle(JL.redOnInk)
        } else {
            Circle()
                .fill(state.paused ? Color(hex: 0x9A9284) : JL.redOnInk)
                .frame(width: 10, height: 10)
        }
    }
}

/// "0.57 KM TO TIKTOK", or "TIKTOK IS YOURS" once unlocked.
private struct Headline: View {
    let app: String
    let state: RunActivityAttributes.ContentState
    var size: CGFloat = 44

    var body: some View {
        if state.unlocked {
            Text("\(app) is yours")
                .font(.jlHeading(size * 0.5))
                .textCase(.uppercase)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", state.remainingMeters / 1_000))
                    .font(.jlDisplay(size))
                    .tracking(-size * 0.04)
                    .monospacedDigit()
                Text("km to \(app)")
                    .font(.jlHeading(size * 0.39))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// The lock screen card: the time, the distance left and the lane.
struct LockScreenRunView: View {
    let app: String
    let startedAt: Date
    let state: RunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("JOG LOCK")
                    .font(.jlHeading(12))
                    .tracking(2)
                if state.paused && !state.unlocked {
                    Text("· PAUSED")
                        .font(.jlHeading(12))
                        .tracking(2)
                        .foregroundStyle(JL.redText)
                }
                Spacer()
                Text(startedAt, style: .timer)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
            Headline(app: app, state: state)
            Lane(progress: state.unlocked ? 1 : state.progress)
                .frame(height: 22)
        }
        .foregroundStyle(JL.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

/// A red lane with lane lines, ink up to the runner.
private struct Lane: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let x = max(height / 2, min(width - height / 2, width * progress))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(JL.red)
                Canvas { context, size in
                    var lines = Path()
                    for y in stride(from: 6.0, to: Double(size.height), by: 7) {
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.white.opacity(0.5)), lineWidth: 1)
                }
                .clipShape(Capsule())
                Capsule()
                    .fill(JL.ink)
                    .frame(width: x + height / 2)
                Circle()
                    .fill(JL.card)
                    .overlay(Circle().strokeBorder(JL.ink, lineWidth: 3))
                    .frame(width: height, height: height)
                    .offset(x: x - height / 2)
            }
        }
    }
}
