//
//  ShieldConfigurationExtension.swift
//  JogLockShield
//
//  What you see when you open a locked app: track red, Jog Lock's mark,
//  "TikTok is 1.8 km away", a line that changes each minute, and the
//  banked minutes if there are any. Run-only apps get warm paper instead.
//  Only this extension gets the app's name; Jog Lock never sees it. It
//  reads the lock's state without the lock and never saves it.
//

import JogLockCore
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName) { LockShield.isRunOnly($0, application: application.token) }
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: application.localizedDisplayName ?? category.localizedDisplayName) {
            LockShield.isRunOnly($0, application: application.token, category: category.token)
        }
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(for: webDomain.domain) { LockShield.isRunOnly($0, website: webDomain.token) }
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        shield(for: webDomain.domain ?? category.localizedDisplayName) {
            LockShield.isRunOnly($0, category: category.token, website: webDomain.token)
        }
    }

    /// `runOnly`: whether this shield is the run-only apps' rather than the daily lock's.
    /// The daily lock is track red with paper writing; run-only apps are
    /// warm paper with ink, since they only wait for a run.
    private func shield(for name: String?, runOnly: (LockState) -> Bool) -> ShieldConfiguration {
        let now = Date()
        var state = LockStore.peek()
        if let rules = state?.rules {
            state?.ledger.update(to: now, rules: rules)
        }
        let forRuns = state.map(runOnly) ?? false
        let ground = forRuns ? Self.paper : Self.red
        let writing = forRuns ? Self.ink : Self.card
        // The colour tints the blur; with no blur iOS ignores it (Tilawah Key,
        // export 53). Fully opaque, the tint is all that shows.
        return ShieldConfiguration(
            backgroundBlurStyle: forRuns ? .systemUltraThinMaterialLight : .systemUltraThinMaterialDark,
            backgroundColor: ground,
            icon: Self.mark(color: writing),
            title: ShieldConfiguration.Label(
                text: forRuns ? ShieldText.runOnlyTitle(app: name)
                    : ShieldText.title(app: name, remainingMeters: state.map { $0.ledger.remainingMeters(rules: $0.rules) } ?? 0),
                color: writing),
            subtitle: ShieldConfiguration.Label(
                text: forRuns ? ShieldText.runOnlySubtitle
                    : state.map { ShieldText.subtitle($0.ledger, rules: $0.rules, at: now) } ?? ShieldText.line(at: now),
                color: writing.withAlphaComponent(0.88)),
            primaryButtonLabel: ShieldConfiguration.Label(text: ShieldText.button, color: forRuns ? Self.card : Self.ink),
            primaryButtonBackgroundColor: forRuns ? Self.red : Self.card,
            secondaryButtonLabel: ShieldConfiguration.Label(text: ShieldText.close, color: writing))
    }

    // Race Day colours: the extension doesn't have the app's theme.
    private static let red = UIColor(red: 0.784, green: 0.196, blue: 0.102, alpha: 1)       // JL.red
    private static let card = UIColor(red: 1, green: 0.992, blue: 0.973, alpha: 1)          // JL.card
    private static let paper = UIColor(red: 0.929, green: 0.906, blue: 0.859, alpha: 1)     // #EDE7DB
    private static let ink = UIColor(red: 0.09, green: 0.078, blue: 0.059, alpha: 1)        // JL.ink

    /// Jog Lock's mark: a running track with a padlock in the infield.
    private static func mark(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 96, height: 64)).image { _ in
            color.setStroke()
            let outer = UIBezierPath(roundedRect: CGRect(x: 3, y: 3, width: 90, height: 58), cornerRadius: 29)
            outer.lineWidth = 5
            outer.stroke()
            color.withAlphaComponent(0.55).setStroke()
            let inner = UIBezierPath(roundedRect: CGRect(x: 14, y: 14, width: 68, height: 36), cornerRadius: 18)
            inner.lineWidth = 2
            inner.stroke()
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 39, y: 30, width: 18, height: 14), cornerRadius: 3).fill()
            color.setStroke()
            let shackle = UIBezierPath()
            shackle.move(to: CGPoint(x: 42, y: 30))
            shackle.addLine(to: CGPoint(x: 42, y: 26))
            shackle.addArc(withCenter: CGPoint(x: 48, y: 26), radius: 6, startAngle: .pi, endAngle: 0, clockwise: true)
            shackle.addLine(to: CGPoint(x: 54, y: 30))
            shackle.lineWidth = 3
            shackle.stroke()
        }
    }
}
