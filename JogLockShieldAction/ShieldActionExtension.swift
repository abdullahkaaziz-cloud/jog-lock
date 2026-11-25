//
//  ShieldActionExtension.swift
//  JogLockShieldAction
//
//  The shield's buttons. Run now opens Jog Lock on iOS 26.5 and later; on
//  older iOS a shield can't open an app, so it sends a notification that
//  does, and closes the locked app. Close only closes. Neither ever opens
//  the locked app. From Tilawah Key's Read now.
//

import Foundation
import JogLockCore
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, blocked: "app", completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, blocked: "website", completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, blocked: "category", completionHandler)
    }

    private func respond(to action: ShieldAction, blocked: String,
                         _ completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            Self.record("close", blocked: blocked)
            completionHandler(.close)
            return
        }
        if #available(iOS 26.5, *) {
            Self.record("run-now", blocked: blocked, note: "opens Jog Lock")
            completionHandler(.openParentalControlsApp)
            return
        }
        let minutes = LockStore.peek()?.ledger.spendableMinutes ?? 0
        // iOS calls the handler once, from any thread.
        nonisolated(unsafe) let done = completionHandler
        Task {
            let note = await RunNowReminder.send(bankMinutes: minutes)
            Self.record("run-now", blocked: blocked, note: note)
            done(.close)
        }
    }

    private static func record(_ button: String, blocked: String, note: String? = nil) {
        var entry: [String: Any] = ["time": DiagnosticLog.now(), "button": button, "blocked": blocked]
        if let note {
            entry["note"] = note
        }
        LockStore.shieldLog?.append(entry)
    }
}
