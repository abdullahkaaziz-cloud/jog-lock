//
//  LockStore.swift
//  Built into the app and its Screen Time extensions (monitor and shield).
//
//  The lock's state lives in the App Group so the extensions can read it:
//  whether the lock is on, the chosen apps, the rules and today's ledger.
//  LockShield makes iOS match it: the chosen apps are shielded unless
//  today's run is done or an unlock session is on.
//

import FamilyControls
import Foundation
import JogLockCore
import ManagedSettings

enum LockStore {
    static let appGroup = "group.com.abdullahaziz.JogLockTracker"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private enum Keys {
        static let enabled = "lock.enabled"
        static let selection = "lock.selection"
        static let rules = "lock.rules"
        static let ledger = "lock.ledger"
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// The apps, categories and websites to lock.
    static var selection: FamilyActivitySelection {
        get { load(FamilyActivitySelection.self, key: Keys.selection) ?? FamilyActivitySelection() }
        set { save(newValue, key: Keys.selection) }
    }

    static var rules: LockRules {
        get { load(LockRules.self, key: Keys.rules) ?? LockRules() }
        set { save(newValue, key: Keys.rules) }
    }

    /// Today's ledger, brought up to `now` (a new day, a finished session).
    /// The shield extension reads without saving.
    static func ledger(at now: Date = Date(), saving: Bool = true) -> LockLedger {
        let rules = self.rules
        guard var ledger = load(LockLedger.self, key: Keys.ledger) else {
            let fresh = LockLedger(day: LockDay(now), rules: rules)
            if saving {
                save(fresh, key: Keys.ledger)
            }
            return fresh
        }
        if ledger.update(to: now, rules: rules) && saving {
            save(ledger, key: Keys.ledger)
        }
        return ledger
    }

    /// Changes today's ledger and saves it. Returns what `change` returns.
    @discardableResult
    static func changeLedger<T>(at now: Date = Date(), _ change: (inout LockLedger) throws -> T) rethrows -> T {
        var ledger = self.ledger(at: now)
        let result = try change(&ledger)
        save(ledger, key: Keys.ledger)
        return result
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

enum LockShield {
    private static let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("joglock"))

    /// Shields or opens the chosen apps to match the lock at `now`. Safe to
    /// call from anywhere, any number of times.
    static func apply(at now: Date = Date()) {
        let ledger = LockStore.ledger(at: now)
        if LockStore.isEnabled && !ledger.isUnlocked(at: now) {
            shield(LockStore.selection)
        } else {
            open()
        }
    }

    static func open() {
        store.clearAllSettings()
    }

    private static func shield(_ selection: FamilyActivitySelection) {
        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        let sites = selection.webDomainTokens
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty
            ? nil : ShieldSettings.ActivityCategoryPolicy.specific(categories)
        store.shield.webDomains = sites.isEmpty ? nil : sites
        store.shield.webDomainCategories = categories.isEmpty
            ? nil : ShieldSettings.ActivityCategoryPolicy.specific(categories)
    }
}
