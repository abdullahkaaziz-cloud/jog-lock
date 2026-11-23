//
//  LockShield.swift
//  Built into the app and its Screen Time extensions.
//
//  The only code that turns the chosen apps into iOS shields, in one named
//  store, so clearing it never touches anything else. From Tilawah Key's
//  ScreenTimeShield, with its limits and its web filter.
//

import FamilyControls
import Foundation
import JogLockCore
import ManagedSettings

enum LockShield {
    /// iOS shields at most 50 apps from one store; categories have no limit.
    static let appLimit = 50
    /// iOS's web filter was reported to stop working past 49 websites.
    static let websiteLimit = 40

    private static let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("joglock"))

    static func encode(_ selection: FamilyActivitySelection) throws -> Data {
        try JSONEncoder().encode(selection)
    }

    static func decode(_ data: Data) throws -> FamilyActivitySelection {
        try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    /// Why a selection can't be locked, or nil if it can.
    static func problem(with selection: FamilyActivitySelection) -> String? {
        let apps = selection.applicationTokens.count
        let websites = selection.webDomainTokens.count
        if apps + selection.categoryTokens.count + websites == 0 {
            return "Choose at least one app, category or website."
        }
        if apps > appLimit {
            return "iOS can lock at most \(appLimit) apps. Choose fewer, or a whole category."
        }
        if websites > websiteLimit {
            return "Choose at most \(websiteLimit) websites."
        }
        return nil
    }

    /// Shields the apps or lifts the shield, as the state says. If the
    /// chosen apps can't be read, the shield is left as it is.
    static func apply(_ state: LockState) throws {
        guard state.shields else {
            open()
            return
        }
        guard let data = state.selection else { throw LockFailure.state }
        shield(try decode(data))
    }

    /// Apps, apps through their category, and websites alike. iOS never
    /// shields Jog Lock itself.
    static func shield(_ selection: FamilyActivitySelection) {
        let categories = selection.categoryTokens
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
        // Shields reach websites in Safari only. iOS's web filter covers Chrome
        // and other browsers too (and turns off Safari's private browsing
        // while it's set).
        let websites = Set(selection.webDomainTokens.map { WebDomain(token: $0) })
        store.webContent.blockedByFilter = websites.isEmpty ? nil : .specific(websites)
    }

    static func open() {
        store.clearAllSettings()
    }

    /// For the diagnostics: how many of each were chosen, never which.
    static func counts(_ data: Data?) -> String? {
        guard let data, let selection = try? decode(data) else { return nil }
        return "\(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, "
            + "\(selection.webDomainTokens.count) websites"
    }
}

enum LockFailure: LocalizedError {
    case sharedContainer, state, busy

    var errorDescription: String? {
        switch self {
        case .sharedContainer:
            "The app lock needs its App Group. Check signing for Jog Lock and its extensions."
        case .state:
            "The lock's saved state couldn't be read safely, so nothing was changed."
        case .busy:
            "The lock is busy with another change. Try again in a moment."
        }
    }
}
