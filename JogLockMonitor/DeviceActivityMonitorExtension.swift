//
//  DeviceActivityMonitorExtension.swift
//  JogLockMonitor
//
//  iOS wakes this at midnight and when an unlock session ends, so the apps
//  lock again even if Jog Lock itself isn't running.
//

import DeviceActivity
import Foundation
import JogLockCore

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == .lockDay {
            // A new day: locked until today's run.
            LockShield.apply()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .lockSession {
            let now = Date()
            LockStore.changeLedger(at: now) { $0.endSession(ifDueBy: now) }
            LockShield.apply(at: now)
        }
    }
}
