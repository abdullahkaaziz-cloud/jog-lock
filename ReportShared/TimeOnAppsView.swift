//
//  TimeOnAppsView.swift
//  Built into the app and its report extension.
//
//  The numbers in the home screen's Time on apps card: a day on average
//  this week against last week, what this week's time would take to run
//  for, and the apps used most. Drawn with Screen Time's numbers only by
//  the report extension (JogLockReport). The app draws it hidden at its
//  tallest, to size the card, because the extension can't say how tall it
//  is. From Tilawah Key's TimeOnAppsReport (H5, D94).
//

import JogLockCore
import SwiftUI

struct TimeOnAppsView<Icon: View>: View {
    let week: ScreenTimeWeek
    /// An app's icon: Screen Time's in the extension, nothing in the app.
    @ViewBuilder var icon: (ScreenTimeWeek.AppTime) -> Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if week.isEmpty {
                Text("Nothing from Screen Time yet this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    line(Text("A day on average").font(.subheadline.weight(.semibold)),
                         Text(ScreenTimeWeek.text(week.total.perDay)).font(.title3.weight(.bold)))
                    if let change = week.change(week.total) {
                        Text(change)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let running = week.running(minutesPerKm: LockRules().minutesPerExtraKm) {
                        Text(running)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !week.apps.isEmpty {
                    Divider()
                    Text("Most used this week")
                        .font(.subheadline.weight(.semibold))
                    ForEach(week.apps) { app in
                        row(app)
                    }
                }
                if !week.lastWeekRecorded {
                    Text("Nothing from last week to compare with yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ app: ScreenTimeWeek.AppTime) -> some View {
        HStack(spacing: 12) {
            icon(app)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                line(Text(app.name).font(.body),
                     Text(ScreenTimeWeek.text(app.time.perDay)).font(.subheadline.weight(.semibold)))
                if let change = week.change(app.time) {
                    Text(change)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A name and its time on one line, the name cut short if it must be.
    private func line(_ name: Text, _ time: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            name.lineLimit(1)
            Spacer(minLength: 8)
            time.monospacedDigit()
                .fixedSize()
        }
    }
}
