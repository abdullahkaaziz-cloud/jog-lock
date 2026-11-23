//
//  ShieldConfigurationExtension.swift
//  JogLockShield
//
//  What you see when you open a locked app: "TikTok is 1.8 km away", a
//  line that changes each minute, and the banked minutes if there are any.
//  Only this extension gets the app's name; Jog Lock never sees it. It
//  reads the lock's state without the lock and never saves it.
//

import JogLockCore
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName ?? category.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(for: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: webDomain.domain ?? category.localizedDisplayName)
    }

    private func shield(for name: String?) -> ShieldConfiguration {
        let now = Date()
        var state = LockStore.peek()
        if let rules = state?.rules {
            state?.ledger.update(to: now, rules: rules)
        }
        let ledger = state?.ledger
        let green = UIColor.systemGreen
        let icon = UIImage(systemName: "figure.run",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .bold))?
            .withTintColor(green, renderingMode: .alwaysOriginal)
        // The colour tints the blur; with no blur iOS ignores it (Tilawah Key, export 53).
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.6),
            icon: icon,
            title: ShieldConfiguration.Label(
                text: ShieldText.title(app: name, remainingMeters: ledger?.remainingMeters ?? 0), color: .white),
            subtitle: ShieldConfiguration.Label(
                text: ledger.map { ShieldText.subtitle($0, at: now) } ?? ShieldText.line(at: now),
                color: UIColor(white: 0.85, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: ShieldText.button, color: .black),
            primaryButtonBackgroundColor: green,
            secondaryButtonLabel: ShieldConfiguration.Label(text: ShieldText.close, color: .white))
    }
}
