//
//  ShieldConfigurationExtension.swift
//  JogLockShield
//
//  What you see when you open a locked app: "TikTok is 1.8 km away".
//  Only this extension gets the app's name; the main app never sees it.
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
        let ledger = LockStore.ledger(saving: false)
        let icon = UIImage(systemName: "figure.run",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .bold))?
            .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.6),
            icon: icon,
            title: ShieldConfiguration.Label(text: ShieldText.title(app: name, remainingMeters: ledger.remainingMeters),
                                             color: .white),
            subtitle: ShieldConfiguration.Label(text: ShieldText.subtitle(ledger),
                                                color: UIColor(white: 0.85, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: ShieldText.button, color: .black),
            primaryButtonBackgroundColor: .systemGreen,
            secondaryButtonLabel: nil)
    }
}
