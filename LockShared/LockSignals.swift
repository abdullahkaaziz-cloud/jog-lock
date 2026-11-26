//
//  LockSignals.swift
//  Built into the app and its Screen Time extensions.
//
//  How the parts tell each other and the runner things, from Tilawah Key:
//  a signal from the monitor to the open app, the "1 minute left"
//  notification, and the shield's Run now notification on iOS before 26.5.
//

import Foundation
import notify
import Synchronization
import UserNotifications

/// The monitor tells the app it changed the lock, so an open app updates at
/// once. A Darwin notification carries nothing and only reaches an app
/// that's running; the app catches up when it opens anyway.
enum LockSignal {
    static let name = "com.abdullahaziz.JogLockTracker.lock-changed"
    /// Posted in the app for each signal received.
    static let received = Notification.Name("LockSignalReceived")
    @MainActor private static var token = NOTIFY_TOKEN_INVALID

    static func post() {
        notify_post(name)
    }

    @MainActor static func listen() {
        guard token == NOTIFY_TOKEN_INVALID else { return }
        notify_register_dispatch(name, &token, .main) { _ in
            NotificationCenter.default.post(name: received, object: nil)
        }
    }
}

/// A notification a minute before the apps lock again, as banked minutes run
/// out. The monitor sends it as it counts the minute before the last; one at
/// a time, so a second replaces the first.
enum LockAgainNotice {
    static let identifier = "lock-again"
    /// Waited for at most this long: iOS may end the monitor once it returns.
    static let wait: TimeInterval = 2

    /// Returns what happened, for the monitor's log.
    static func send() -> String {
        let done = DispatchSemaphore(value: 0)
        let outcome = Outcome()
        // Detached: the caller waits below, so the task must never need its thread.
        Task.detached {
            let content = UNMutableNotificationContent()
            content.title = "Your apps lock again in 1 minute"
            content.body = "Then it's back to running for them."
            do {
                try await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                outcome.set(status == .denied || status == .notDetermined ? "queued, notifications off" : "queued")
            } catch {
                outcome.set("not queued: \(error.localizedDescription)")
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + wait) == .success else { return "not confirmed in \(Int(wait)) s" }
        return outcome.value
    }

    private final class Outcome: Sendable {
        private let note = Mutex("")
        var value: String { note.withLock { $0 } }
        func set(_ value: String) { note.withLock { $0 = value } }
    }
}

/// Before iOS 26.5 a shield can't open Jog Lock, so its Run now button sends
/// this notification, and tapping it opens the app. From iOS 26.5 the shield
/// asks iOS to open Jog Lock itself. Neither ever opens the locked app.
enum RunNowReminder {
    static let identifier = "run-now"

    static var opensApp: Bool {
        if #available(iOS 26.5, *) {
            return true
        }
        return false
    }

    /// Returns what happened, for the shield's log.
    static func send(bankMinutes: Int) async -> String {
        let content = UNMutableNotificationContent()
        content.title = "Time to run"
        content.body = bankMinutes > 0
            ? "Tap to open Jog Lock and start a run, or to use your \(bankMinutes) banked minutes."
            : "Tap to open Jog Lock and start a run."
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            return "notification queued"
        } catch {
            return "notification not queued: \(error.localizedDescription)"
        }
    }
}
