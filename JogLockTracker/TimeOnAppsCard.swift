//
//  TimeOnAppsCard.swift
//  JogLockTracker
//
//  The home screen's Time on apps card, once Screen Time is connected: its
//  title here, its numbers drawn by the report extension (JogLockReport),
//  which alone sees them. With the lock on it reports on the locked apps;
//  otherwise on every app.
//

import DeviceActivity
import JogLockCore
import SwiftUI
import UIKit

struct TimeOnAppsCard: View {
    @EnvironmentObject private var lock: AppLock

    var body: some View {
        let locked = lock.isEnabled && lock.hasPickedApps
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(locked ? "Time on your locked apps" : "Your time on apps",
                      systemImage: "hourglass.bottomhalf.filled")
                    .font(.headline)
                Text("This week against last, from Screen Time. Only iOS sees which apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The extension can't say how tall it is, so the report fills the
            // space the same report takes at its tallest, drawn hidden
            // beneath it. With fewer apps the card ends in space.
            TimeOnAppsView(week: .tallest) { _ in Color.clear }
                .hidden()
                .overlay {
                    DeviceActivityReport(.timeOnApps, filter: locked
                                         ? .timeOnApps(lock.selection, now: Date())
                                         : .timeOnApps(now: Date()))
                }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
