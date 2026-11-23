//
//  AppLock.swift
//  JogLockTracker
//
//  The app's side of the lock: Screen Time permission, the chosen apps,
//  and turning runs, banked minutes and borrowing into unlocks. The state
//  itself lives in LockStore (shared with the extensions).
//

import FamilyControls
import Foundation
import JogLockCore

@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var selection: FamilyActivitySelection
    @Published private(set) var rules: LockRules
    @Published private(set) var ledger: LockLedger
    /// True when a run has just opened the apps: shows the unlock celebration.
    @Published var celebrating = false
    @Published var problem: String?

    /// Run distance last saved to the shared ledger, by run.
    private var savedMeters: [String: Double] = [:]

    private init() {
        isEnabled = LockStore.isEnabled
        selection = LockStore.selection
        rules = LockStore.rules
        ledger = LockStore.ledger()
    }

    var hasChosenApps: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: - Turning it on and off

    /// Asks for Screen Time access (Face ID or passcode). True if granted.
    func authorize() async -> Bool {
        if isAuthorized {
            return true
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            problem = "Jog Lock needs Screen Time access to lock apps. \(error.localizedDescription)"
        }
        return isAuthorized
    }

    /// Saves the apps picked in the Screen Time picker; turns the lock on
    /// if there are any, off if there are none.
    func choose(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        LockStore.selection = newSelection
        if hasChosenApps {
            turnOn()
        } else if isEnabled {
            turnOff()
        }
    }

    private func turnOn() {
        do {
            try LockSchedule.startDaily()
        } catch {
            problem = "Couldn't set up the midnight lock: \(error.localizedDescription)"
            return
        }
        if !isEnabled {
            // Today's runs so far count against today's target.
            let now = Date()
            let rules = LockStore.rules
            LockStore.changeLedger(at: now) { $0.resetTarget(rules: rules, at: now) }
        }
        isEnabled = true
        LockStore.isEnabled = true
        refresh()
    }

    func turnOff() {
        isEnabled = false
        LockStore.isEnabled = false
        LockSchedule.stopAll()
        LockShield.open()
        refresh()
    }

    /// Catches up: a new day, a finished session, the shield. Called when
    /// the app comes to the front.
    func refresh(at now: Date = Date()) {
        rules = LockStore.rules
        ledger = LockStore.ledger(at: now)
        if isEnabled {
            try? LockSchedule.startDaily()
            LockShield.apply(at: now)
        }
    }

    /// The daily distance setting. While the lock is on, today's target
    /// stays and the new one starts tomorrow.
    func setDailyKm(_ km: Double) {
        var rules = LockStore.rules
        guard rules.dailyMeters != km * 1_000 else { return }
        rules.dailyMeters = km * 1_000
        LockStore.rules = rules
        self.rules = rules
        if !isEnabled {
            let now = Date()
            ledger = LockStore.changeLedger(at: now) { ledger in
                ledger.resetTarget(rules: rules, at: now)
                return ledger
            }
        }
    }

    // MARK: - Runs

    /// What the next run has to cover: what's left of today's target while
    /// the apps are locked, otherwise the usual setting.
    func runTargetKm(default km: Double) -> Double {
        refresh()
        guard isEnabled, !ledger.isTargetMet, ledger.remainingMeters > 0 else { return km }
        return ledger.remainingMeters / 1_000
    }

    /// A run's counted distance so far. Saved to the shared ledger every
    /// 25 m, at the unlock and at the end, so the shield's "1.8 km away"
    /// stays close.
    func credit(run id: String, countedMeters: Double, at now: Date = Date(), finished: Bool = false) {
        var preview = ledger
        preview.update(to: now, rules: rules)
        let unlocks = preview.credit(run: id, countedMeters: countedMeters, rules: rules, at: now)
        if unlocks || finished || countedMeters - (savedMeters[id] ?? 0) >= 25 {
            savedMeters[id] = countedMeters
            let rules = self.rules
            ledger = LockStore.changeLedger(at: now) { ledger in
                ledger.credit(run: id, countedMeters: countedMeters, rules: rules, at: now)
                return ledger
            }
        } else if preview != ledger {
            ledger = preview
        }
        if finished {
            savedMeters[id] = nil
        }
        if unlocks && isEnabled {
            LockShield.apply(at: now)
            celebrating = true
        }
    }

    // MARK: - Banked minutes and borrowing

    func spend(minutes: Double) {
        startSession { ledger, now in try ledger.spend(minutes: minutes, at: now) }
    }

    func borrow() {
        let rules = self.rules
        startSession { ledger, now in try ledger.borrow(rules: rules, at: now) }
    }

    private func startSession(_ make: (inout LockLedger, Date) throws -> UnlockSession) {
        let now = Date()
        do {
            let session = try LockStore.changeLedger(at: now) { try make(&$0, now) }
            do {
                try LockSchedule.start(session)
            } catch {
                LockStore.changeLedger(at: now) { $0.cancel(session) }
                problem = "iOS wouldn't time the unlock, so it's been cancelled. \(error.localizedDescription)"
            }
        } catch let error as LockError {
            problem = Self.message(for: error)
        } catch {
            problem = error.localizedDescription
        }
        refresh(at: now)
    }

    nonisolated static func message(for error: LockError) -> String {
        switch error {
        case .alreadyUnlocked:
            "Your apps are already open."
        case .tooShort:
            "Unlocks are at least 15 minutes. iOS can't time anything shorter."
        case .notEnoughMinutes(let available):
            "You've only got \(Int(available)) banked minutes."
        case .alreadyBorrowedToday:
            "You've already borrowed from tomorrow today."
        case .owedLimit(let owed):
            "You already owe \(Format.shortDistance(owed)). Run that off before borrowing more."
        }
    }
}
