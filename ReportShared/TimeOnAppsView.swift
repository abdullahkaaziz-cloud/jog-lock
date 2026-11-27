//
//  TimeOnAppsView.swift
//  Built into the app and its report extension.
//
//  The numbers on the home screen's Time on apps receipt: a day on average
//  this week against last week, the apps used most, and what this week's
//  time would take to run for. Drawn with Screen Time's numbers only by the
//  report extension (JogLockReport). The app draws it hidden at its
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
        let rate = LockRules().minutesPerExtraKm
        VStack(alignment: .leading, spacing: 8) {
            if week.isEmpty {
                Text("NOTHING FROM SCREEN TIME YET THIS WEEK.")
                    .font(Receipt.small)
                    .foregroundStyle(Receipt.faded)
            } else {
                ReceiptLine(label: "A DAY, THIS WEEK", value: ScreenTimeWeek.text(week.total.perDay), bold: true)
                if week.lastWeekRecorded {
                    ReceiptLine(label: "A DAY, LAST WEEK", value: ScreenTimeWeek.text(week.total.lastWeekPerDay))
                }
                if let change = week.change(week.total) {
                    Text(change.uppercased())
                        .font(Receipt.small)
                        .foregroundStyle(Receipt.faded)
                }
                if !week.apps.isEmpty {
                    ReceiptRule()
                    Text("MOST USED, A DAY")
                        .font(Receipt.small)
                        .foregroundStyle(Receipt.faded)
                    ForEach(week.apps) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                icon(app)
                                    .frame(width: 22, height: 22)
                                ReceiptLine(label: app.name.uppercased(), value: ScreenTimeWeek.text(app.time.perDay))
                            }
                            if let change = week.change(app.time) {
                                Text(change)
                                    .font(Receipt.small)
                                    .foregroundStyle(Receipt.faded)
                                    .padding(.leading, 30)
                            }
                        }
                    }
                }
                ReceiptRule()
                ReceiptLine(label: "THIS WEEK SO FAR", value: ScreenTimeWeek.text(week.total.thisWeek))
                if let owed = week.owedMeters(minutesPerKm: rate) {
                    ReceiptLine(label: "OWED AT \(Int(rate)) MIN/KM", value: Format.shortDistance(owed), bold: true)
                }
            }
        }
        .foregroundStyle(Receipt.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
