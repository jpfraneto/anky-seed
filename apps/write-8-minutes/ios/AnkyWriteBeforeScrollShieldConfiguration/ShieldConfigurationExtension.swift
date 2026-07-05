import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        WriteBeforeScrollLaunchBridgeStore().saveLastAttemptedAppDisplayName(application.localizedDisplayName)
        return configuration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration()
    }

    private func configuration() -> ShieldConfiguration {
        let bridgeMode = WriteBeforeScrollLaunchBridgeModeResolver.resolve()
        let bridgeStore = WriteBeforeScrollLaunchBridgeStore()
        let fallbackState = bridgeStore.currentFallbackShieldState()
        let quickPassesRemaining = QuickPassStore().remainingPasses()
        let copy = bridgeStore.copy(
            bridgeMode: bridgeMode,
            fallbackState: fallbackState,
            quickPassesRemaining: quickPassesRemaining,
            attemptedAppName: bridgeStore.lastAttemptedAppDisplayName()
        )
        WriteBeforeScrollEventLogStore().append(
            .shieldRendered,
            metadata: [
                "bridgeMode": bridgeMode.rawValue,
                "fallbackState": "\(fallbackState)",
                "quickPassesRemaining": "\(quickPassesRemaining)"
            ]
        )
        if quickPassesRemaining == 0 {
            WriteBeforeScrollEventLogStore().append(.quickPassExhaustedShown)
        }
        // Never pure black: the gate is a warm aubergine dusk with parchment
        // light in the button — darkness that is alive.
        let aubergine = UIColor(red: 0.16, green: 0.10, blue: 0.17, alpha: 1)
        let parchment = UIColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1)
        let ink = UIColor(red: 0.16, green: 0.13, blue: 0.22, alpha: 1)
        let goldLight = UIColor(red: 0.96, green: 0.85, blue: 0.63, alpha: 1)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: aubergine,
            title: ShieldConfiguration.Label(text: copy.title, color: goldLight),
            subtitle: ShieldConfiguration.Label(text: copy.subtitle, color: parchment),
            primaryButtonLabel: ShieldConfiguration.Label(text: copy.primaryButton, color: ink),
            primaryButtonBackgroundColor: parchment,
            secondaryButtonLabel: ShieldConfiguration.Label(text: copy.secondaryButton, color: parchment.withAlphaComponent(0.8))
        )
    }
}
