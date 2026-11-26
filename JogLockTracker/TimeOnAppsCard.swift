//
//  TimeOnAppsCard.swift
//  JogLockTracker
//
//  The home screen's Time on apps receipt, once Screen Time is connected.
//  The app draws the paper, the heading and what was paid (km run this
//  week, from the runs kept on the phone). The report extension
//  (JogLockReport) draws Screen Time's numbers in the middle; only it sees
//  them. With the lock on it reports on the locked apps; otherwise on every
//  app. Made to be screenshotted.
//

import DeviceActivity
import JogLockCore
import SwiftUI

struct TimeOnAppsCard: View {
    @EnvironmentObject private var lock: AppLock
    @State private var paidMeters: Double = 0

    var body: some View {
        let locked = lock.isEnabled && lock.hasPickedApps
        let now = Date()
        let weekStart = ScreenTimeWeek.thisWeek(from: ScreenTimeWeek.fortnight(of: now))
        VStack(spacing: 0) {
            ReceiptEdge()
                .fill(Receipt.paper)
                .frame(height: 8)
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 2) {
                    Text("JOG LOCK")
                        .font(Receipt.bold)
                        .tracking(4)
                    Text(locked ? "TIME ON YOUR LOCKED APPS" : "YOUR TIME ON APPS")
                        .font(Receipt.font)
                    Text("WEEK OF \(weekStart.formatted(.dateTime.day().month(.abbreviated)).uppercased())")
                        .font(Receipt.small)
                        .foregroundStyle(Receipt.faded)
                }
                .frame(maxWidth: .infinity)
                ReceiptRule()
                ReceiptLine(label: "PAID: KM RUN", value: paidMeters < 10 ? "0 km" : Format.shortDistance(paidMeters),
                            bold: true)
                ReceiptRule()
                // The extension can't say how tall it is, so the report fills
                // the space the same report takes at its tallest, drawn hidden
                // beneath it. With fewer apps the receipt ends in space.
                TimeOnAppsView(week: .tallest) { _ in Color.clear }
                    .hidden()
                    .overlay {
                        DeviceActivityReport(.timeOnApps, filter: locked
                                             ? .timeOnApps(lock.selection, now: now)
                                             : .timeOnApps(now: now))
                    }
                ReceiptRule()
                if paidMeters >= 10 {
                    Text("PAID")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(Receipt.stamp)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Receipt.stamp, lineWidth: 3))
                        .rotationEffect(.degrees(-8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                Text("FROM SCREEN TIME. ONLY iOS SEES WHICH APPS.\nTHANK YOU FOR RUNNING.")
                    .font(Receipt.small)
                    .foregroundStyle(Receipt.faded)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Receipt.paper)
            ReceiptEdge()
                .fill(Receipt.paper)
                .frame(height: 8)
                .rotationEffect(.degrees(180))
        }
        .foregroundStyle(Receipt.ink)
        .environment(\.colorScheme, .light)
        .shadow(color: Color(hex: 0x3C2814, opacity: 0.12), radius: 14, y: 10)
        .task { paidMeters = Self.paidThisWeek(since: weekStart) }
    }

    /// Counted distance of the runs started this week.
    static func paidThisWeek(since start: Date) -> Double {
        RunStore.onDevice.allSummaries()
            .filter { $0.startedAt >= start }
            .reduce(0) { $0 + ($1.countedMeters ?? $1.cleanMeters) }
    }
}

/// "Time on apps": this week's receipt on its own screen, from the Lock tab.
struct TimeOnAppsScreen: View {
    var body: some View {
        let start = ScreenTimeWeek.thisWeek(from: ScreenTimeWeek.fortnight(of: Date()))
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        ScrollView {
            VStack(spacing: 16) {
                Text("This week · \(start.formatted(.dateTime.day().month(.abbreviated)))–\(end.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.headline)
                TimeOnAppsCard()
                    .padding(.horizontal, 4)
                Text("From Screen Time on this iPhone. Only you can see it, not even Jog Lock.")
                    .font(.footnote)
                    .foregroundStyle(JL.ink2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(JL.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .jlScreen()
        .navigationTitle("Time on apps")
        .navigationBarTitleDisplayMode(.inline)
    }
}
