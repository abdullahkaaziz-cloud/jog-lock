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
    /// Websites chosen and typed in together: iOS's web filter was reported
    /// to stop working past 49.
    static let websiteLimit = TypedWebsite.limit

    private static let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("joglock"))

    static func encode(_ selection: FamilyActivitySelection) throws -> Data {
        try JSONEncoder().encode(selection)
    }

    static func decode(_ data: Data) throws -> FamilyActivitySelection {
        try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    /// Why a selection, with the websites typed in, can't be locked, or nil
    /// if it can.
    static func problem(with selection: FamilyActivitySelection, websites typed: [String] = []) -> String? {
        let apps = selection.applicationTokens.count
        let websites = selection.webDomainTokens.count + typed.count
        if apps + selection.categoryTokens.count + websites == 0 {
            return "Choose at least one app, category or website."
        }
        if apps > appLimit {
            return "iOS can lock at most \(appLimit) apps. Choose fewer, or a whole category."
        }
        if websites > websiteLimit {
            return "Up to \(websiteLimit) websites in all, chosen and typed."
        }
        return nil
    }

    /// Shields the apps or lifts the shield, as the state says. If the
    /// chosen apps can't be read, the shield is left as it is.
    static func apply(_ state: LockState) throws {
        applyRunOnly(state)
        guard state.shields else {
            open()
            return
        }
        guard let data = state.selection else { throw LockFailure.state }
        shield(try decode(data), websites: state.websites)
    }

    /// Apps, apps through their category, and websites alike, chosen or
    /// typed in. iOS never shields Jog Lock itself.
    static func shield(_ selection: FamilyActivitySelection, websites typed: [String]) {
        let categories = selection.categoryTokens
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
        // Shields reach websites in Safari only. iOS's web filter covers Chrome
        // and other browsers too (and turns off Safari's private browsing
        // while it's set). It takes the chosen websites as tokens and the
        // typed ones by name; those get iOS's own "restricted" page.
        let websites = Set(selection.webDomainTokens.map { WebDomain(token: $0) }
            + TypedWebsite.cleaned(typed).map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = websites.isEmpty ? nil : .specific(websites)
    }

    static func open() {
        store.clearAllSettings()
    }

    /// For the diagnostics: how many of each were chosen, never which.
    static func counts(_ state: LockState) -> String? {
        guard let data = state.selection, let selection = try? decode(data) else { return nil }
        return "\(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, "
            + "\(selection.webDomainTokens.count) websites, \(state.websites.count) typed"
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

// MARK: - Run-only apps

extension LockShield {
    /// Run-only apps have their own store, so opening them for a run leaves
    /// the daily lock alone. iOS shields an app if any store does.
    private static let runStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("joglock-run"))

    /// Shields the run-only apps unless a run has them open.
    static func applyRunOnly(_ state: LockState, at now: Date = Date()) {
        guard let data = state.runOnly, let selection = try? decode(data), !state.runOnlyOpen(at: now) else {
            runStore.clearAllSettings()
            return
        }
        runStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        runStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        runStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    /// Whether the shield on this app, category or website is the run-only one rather than the daily lock's.
    static func isRunOnly(_ state: LockState, application: ApplicationToken? = nil,
                          category: ActivityCategoryToken? = nil, website: WebDomainToken? = nil) -> Bool {
        guard let data = state.runOnly, let runOnly = try? decode(data) else { return false }
        let locked = state.selection.flatMap { try? decode($0) }
        if let application {
            if locked?.applicationTokens.contains(application) == true && state.shields { return false }
            if runOnly.applicationTokens.contains(application) { return true }
        }
        if let category {
            if locked?.categoryTokens.contains(category) == true && state.shields { return false }
            if runOnly.categoryTokens.contains(category) { return true }
        }
        if let website {
            if locked?.webDomainTokens.contains(website) == true && state.shields { return false }
            if runOnly.webDomainTokens.contains(website) { return true }
        }
        return false
    }
}
