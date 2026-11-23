//
//  TimeOnAppsFilter.swift
//  Built into the app and its report extension.
//
//  The report the home screen asks the report extension to draw, and its
//  days: last week and this one, day by day, on this iPhone. From Tilawah
//  Key's TimeOnAppsFilter (H5, D94).
//

import DeviceActivity
import FamilyControls
import Foundation
import JogLockCore
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    static let timeOnApps = Self("time-on-apps")
}

extension DeviceActivityFilter {
    /// Every app on this iPhone.
    static func timeOnApps(now: Date) -> DeviceActivityFilter {
        DeviceActivityFilter(segment: .daily(during: ScreenTimeWeek.fortnight(of: now)), users: .all,
                             devices: .init([.iPhone]))
    }

    /// The locked apps, categories and websites chosen in Screen Time's
    /// picker. iOS can't report on websites typed in by name.
    static func timeOnApps(_ selection: FamilyActivitySelection, now: Date) -> DeviceActivityFilter {
        DeviceActivityFilter(segment: .daily(during: ScreenTimeWeek.fortnight(of: now)), users: .all,
                             devices: .init([.iPhone]), applications: selection.applicationTokens,
                             categories: selection.categoryTokens, webDomains: selection.webDomainTokens)
    }
}
