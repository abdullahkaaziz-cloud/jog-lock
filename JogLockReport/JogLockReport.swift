//
//  JogLockReport.swift
//  JogLockReport
//
//  The Device Activity Report extension behind the home screen's Time on
//  apps card. iOS hands it Screen Time's minutes for last week and this
//  one, day by day, with each app's name; it adds them up (ScreenTimeWeek)
//  and draws them (TimeOnAppsView). iOS's sandbox keeps them in: it has no
//  App Group, saves nothing and sends nothing, and the app never sees the
//  numbers. From Tilawah Key's ReadingReport (H5, D94).
//

import DeviceActivity
import ExtensionKit
import FamilyControls
import JogLockCore
import ManagedSettings
import SwiftUI

@main
struct JogLockReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TimeOnAppsScene { TimeOnAppsExtensionView(report: $0) }
    }
}

/// The week as worked out, with each app's icon as Screen Time gives it.
/// Screen Time's tokens aren't marked Sendable; a report nobody changes
/// once it's made is safe to hand over.
struct TimeOnApps: @unchecked Sendable {
    let week: ScreenTimeWeek
    let tokens: [String: ApplicationToken]
}

struct TimeOnAppsScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .timeOnApps
    let content: (TimeOnApps) -> TimeOnAppsExtensionView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TimeOnApps {
        var usage: [ScreenTimeWeek.Usage] = []
        var tokens: [String: ApplicationToken] = [:]
        // The days the app asked for: last week's first to this week's last.
        var fortnight = ScreenTimeWeek.fortnight(of: Date())
        for await device in data {
            if case .daily(let days) = device.segmentInterval {
                fortnight = days
            }
            let thisWeek = ScreenTimeWeek.thisWeek(from: fortnight)
            for await day in device.activitySegments {
                let current = day.dateInterval.start >= thisWeek
                for await category in day.categories {
                    for await app in category.applications {
                        let name = app.application.localizedDisplayName ?? app.application.bundleIdentifier ?? ""
                        let key = app.application.bundleIdentifier ?? name
                        guard !key.isEmpty else { continue }
                        if let token = app.application.token {
                            tokens[key] = token
                        }
                        usage.append(ScreenTimeWeek.Usage(key: key, name: name, thisWeek: current,
                                                          seconds: app.totalActivityDuration))
                    }
                    for await site in category.webDomains {
                        guard let domain = site.webDomain.domain, !domain.isEmpty else { continue }
                        usage.append(ScreenTimeWeek.Usage(key: domain, name: domain, website: true, thisWeek: current,
                                                          seconds: site.totalActivityDuration))
                    }
                }
            }
        }
        let days = ScreenTimeWeek.daysThisWeek(since: ScreenTimeWeek.thisWeek(from: fortnight), now: Date())
        return TimeOnApps(week: ScreenTimeWeek(usage: usage, daysThisWeek: days), tokens: tokens)
    }
}

/// The report, with Screen Time's own app icons, on the receipt's paper.
struct TimeOnAppsExtensionView: View {
    let report: TimeOnApps

    var body: some View {
        TimeOnAppsView(week: report.week) { app in
            if let token = report.tokens[app.id] {
                Label(token)
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
        }
        .background(Receipt.paper)
        .environment(\.colorScheme, .light)
        // Nothing here to tap. iOS gives this process every touch over the
        // report, so taking none lets the home screen scroll under a finger
        // that starts on it (Tilawah Key, D95).
        .allowsHitTesting(false)
    }
}
