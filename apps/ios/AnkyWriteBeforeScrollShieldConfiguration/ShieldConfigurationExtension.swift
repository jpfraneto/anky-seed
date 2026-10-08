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

        // The app's own surface (AnkyLazure.swift): ink on paper, nothing else.
        let paper = UIColor(displayP3Red: 0.965, green: 0.937, blue: 0.894, alpha: 1)
        let ink = UIColor(displayP3Red: 0.239, green: 0.216, blue: 0.310, alpha: 1)
        let inkSoft = UIColor(displayP3Red: 0.396, green: 0.369, blue: 0.475, alpha: 1)
        // The button sits on the deepest ink so it can never read as dimmed.
        let buttonInk = UIColor(displayP3Red: 0.11, green: 0.08, blue: 0.14, alpha: 1)

        // A nil blur style makes iOS ignore backgroundColor and paint its own
        // near-black scrim — the light material is what actually carries the
        // paper tone (and holds it even on dark-mode devices).
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialLight,
            backgroundColor: paper,
            icon: shieldMark(ink: ink),
            title: ShieldConfiguration.Label(text: AnkyCopyRegistry.localized("Write before you scroll"), color: ink),
            subtitle: ShieldConfiguration.Label(text: shieldSubtitle(fallbackState: fallbackState), color: inkSoft),
            primaryButtonLabel: ShieldConfiguration.Label(text: shieldPrimaryButtonTitle(fallbackState: fallbackState), color: .white),
            primaryButtonBackgroundColor: buttonInk,
            secondaryButtonLabel: ShieldConfiguration.Label(text: copy.secondaryButton, color: inkSoft)
        )
    }

    /// One line under the title: the invitation, or — once the button has
    /// been pressed — what has to happen next.
    private func shieldSubtitle(fallbackState: WriteBeforeScrollFallbackShieldState) -> String {
        switch fallbackState {
        case .initial:
            return AnkyCopyRegistry.localized("Anky is waiting for you")
        case .notificationSent:
            return AnkyCopyRegistry.localized("Tap the notification to write.")
        case .notificationsDisabled:
            return AnkyCopyRegistry.localized("Notifications are off. Open Anky from your Home Screen.")
        }
    }

    private func shieldPrimaryButtonTitle(fallbackState: WriteBeforeScrollFallbackShieldState) -> String {
        switch fallbackState {
        case .initial:
            return AnkyCopyRegistry.localized("Write")
        case .notificationSent, .notificationsDisabled:
            return AnkyCopyRegistry.localized("Try again")
        }
    }

    /// One ink mark for the one thing asked: a pen. A system glyph costs the
    /// extension almost nothing against its ~6 MB memory ceiling.
    private func shieldMark(ink: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .light)
        return UIImage(systemName: "pencil.line", withConfiguration: configuration)?
            .withTintColor(ink, renderingMode: .alwaysOriginal)
    }
}
