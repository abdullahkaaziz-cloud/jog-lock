//
//  DeviceActivityMonitorExtension.swift
//  JogLockMonitor
//
//  iOS wakes this when the open day's monitor ends (the apps lock again),
//  each minute banked minutes are used (one usage event a minute), and when
//  a day of counting minutes runs out (it's renewed). Each callback is
//  logged for the diagnostics, and the open app is told to catch up.
//

import DeviceActivity
import Foundation
import JogLockCore

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let cycle = LockCycle()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        record("interval-start", activity: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        var notes: [String] = []
        var failure: Error?
        do {
            if let note = try cycle.threshold(monitor: activity.rawValue, event: event.rawValue) {
                notes.append(note)
            }
        } catch {
            failure = error
        }
        // A minute before the apps lock again, a notification says so.
        if let saved = LockStore.peek(), saved.enabled,
           saved.ledger.leavesOneMinute(monitor: activity.rawValue, event: event.rawValue) {
            notes.append("1-minute warning " + LockAgainNotice.send())
        }
        record("threshold", activity: activity, event: event.rawValue,
               note: notes.isEmpty ? nil : notes.joined(separator: "; "), error: failure)
        LockSignal.post()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        var note: String?
        var failure: Error?
        do {
            note = try cycle.intervalEnded(monitor: activity.rawValue)
        } catch {
            failure = error
        }
        record("interval-end", activity: activity, note: note, error: failure)
        LockSignal.post()
    }

    /// Kept for the app's diagnostics, with the state as it is afterwards.
    private func record(_ callback: String, activity: DeviceActivityName, event: String? = nil,
                        note: String? = nil, error: Error? = nil) {
        var entry: [String: Any] = [
            "time": DiagnosticLog.now(), "callback": callback, "monitor": String(activity.rawValue.suffix(8)),
        ]
        if let event {
            entry["event"] = event
        }
        if let note {
            entry["note"] = note
        }
        if let error {
            entry["error"] = error.localizedDescription
        }
        if let state = LockStore.peek() {
            entry["current"] = state.ledger.monitor?.name == activity.rawValue
            entry.merge(LockCycle.summary(state)) { mine, _ in mine }
        }
        LockStore.monitorLog?.append(entry)
    }
}
