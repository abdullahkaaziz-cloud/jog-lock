//
//  LockSchedule.swift
//  Built into the app and its Screen Time extensions.
//
//  iOS only runs Jog Lock's code at set times through DeviceActivity
//  schedules, so these are the lock's alarm clocks: one that starts every
//  midnight (the monitor extension locks the apps again) and one for each
//  unlock session (the apps lock again when it ends).
//

import DeviceActivity
import Foundation
import JogLockCore

extension DeviceActivityName {
    /// All day, every day. Its start at midnight locks the apps again.
    static let lockDay = Self("joglock.day")
    /// One unlock session. Its end locks the apps again.
    static let lockSession = Self("joglock.session")
}

enum LockSchedule {
    /// Starts the midnight re-lock, unless it's already running.
    static func startDaily() throws {
        let center = DeviceActivityCenter()
        guard !center.activities.contains(.lockDay) else { return }
        let schedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
                                              intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                                              repeats: true)
        try center.startMonitoring(.lockDay, during: schedule)
    }

    /// Times an unlock session (at least 15 minutes; iOS refuses shorter).
    /// Times of day only: the form of one-off schedule that reliably fires.
    static func start(_ session: UnlockSession, calendar: Calendar = .current) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.lockSession])
        let parts: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(parts, from: session.start),
                                              intervalEnd: calendar.dateComponents(parts, from: session.end),
                                              repeats: false)
        try center.startMonitoring(.lockSession, during: schedule)
    }

    static func stopAll() {
        DeviceActivityCenter().stopMonitoring()
    }
}
