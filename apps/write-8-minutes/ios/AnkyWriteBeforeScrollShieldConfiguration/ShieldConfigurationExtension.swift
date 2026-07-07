import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(attemptedAppName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(attemptedAppName: application.localizedDisplayName ?? category.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(attemptedAppName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(attemptedAppName: webDomain.domain ?? category.localizedDisplayName)
    }

    private func configuration(attemptedAppName: String?) -> ShieldConfiguration {
        let bridgeMode = WriteBeforeScrollLaunchBridgeModeResolver.resolve()
        let bridgeStore = WriteBeforeScrollLaunchBridgeStore()
        bridgeStore.saveLastAttemptedAppDisplayName(attemptedAppName)
        let fallbackState = bridgeStore.currentFallbackShieldState()
        let quickPassesRemaining = QuickPassStore().remainingPasses()
        let appName = attemptedAppName ?? bridgeStore.lastAttemptedAppDisplayName()
        let copy = bridgeStore.copy(bridgeMode: bridgeMode, fallbackState: fallbackState)
        WriteBeforeScrollEventLogStore().append(
            .shieldRendered,
            metadata: [
                "bridgeMode": bridgeMode.rawValue,
                "fallbackState": "\(fallbackState)",
                "quickPassesRemaining": "\(quickPassesRemaining)",
                "attemptedAppName": appName ?? "unknown"
            ]
        )
        if quickPassesRemaining == 0 {
            WriteBeforeScrollEventLogStore().append(.quickPassExhaustedShown)
        }

        let background = UIColor(red: 0.08, green: 0.055, blue: 0.045, alpha: 1)
        let titleColor = UIColor(red: 0.96, green: 0.86, blue: 0.68, alpha: 1)
        let subtitleColor = UIColor(red: 0.78, green: 0.67, blue: 0.58, alpha: 1)
        let buttonInk = UIColor(red: 0.16, green: 0.10, blue: 0.08, alpha: 1)
        let buttonGold = UIColor(red: 0.82, green: 0.58, blue: 0.29, alpha: 1)
        let subtitle = shieldSubtitle(
            fallbackState: fallbackState,
            fallbackCopy: copy.subtitle,
            appName: appName
        )

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: background,
            icon: shieldArtwork(),
            title: ShieldConfiguration.Label(text: "write with me first.", color: titleColor),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: subtitleColor),
            primaryButtonLabel: ShieldConfiguration.Label(text: shieldPrimaryButtonTitle(fallbackState: fallbackState), color: buttonInk),
            primaryButtonBackgroundColor: buttonGold,
            secondaryButtonLabel: ShieldConfiguration.Label(text: copy.secondaryButton, color: subtitleColor.withAlphaComponent(0.82))
        )
    }

    private func shieldSubtitle(
        fallbackState: WriteBeforeScrollFallbackShieldState,
        fallbackCopy: String,
        appName: String?
    ) -> String {
        var lines = [blockedAppLine(appName: appName)]
        if fallbackState != .initial {
            lines.append(fallbackCopy)
        }
        return lines.joined(separator: "\n\n")
    }

    private func blockedAppLine(appName: String?) -> String {
        guard let appName = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty else {
            return "This app is waiting behind the door."
        }
        return "\(appName) is waiting behind the door."
    }

    private func shieldPrimaryButtonTitle(fallbackState: WriteBeforeScrollFallbackShieldState) -> String {
        switch fallbackState {
        case .initial:
            return "Write ⊙"
        case .notificationSent:
            return "Write ⊙"
        case .notificationsDisabled:
            return "Write ⊙"
        }
    }

    private func shieldArtwork() -> UIImage? {
        let bundle = Bundle(for: Self.self)
        return UIImage(named: "anky_shield_door_icon", in: bundle, compatibleWith: nil)
    }
}
