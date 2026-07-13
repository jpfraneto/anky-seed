import ImageIO
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

        // Lazure pigments (AnkyLazure.swift): the icon's watercolor halo fades
        // into ankyPaper, so the shield background must be that same paper.
        let background = UIColor(displayP3Red: 0.965, green: 0.937, blue: 0.894, alpha: 1)
        let titleColor = UIColor(displayP3Red: 0.239, green: 0.216, blue: 0.310, alpha: 1)
        let subtitleColor = UIColor(displayP3Red: 0.396, green: 0.369, blue: 0.475, alpha: 1)
        let buttonInk = UIColor(displayP3Red: 0.11, green: 0.08, blue: 0.14, alpha: 1)
        let buttonGold = UIColor(displayP3Red: 0.878, green: 0.694, blue: 0.427, alpha: 1)
        let subtitle = shieldSubtitle(
            fallbackState: fallbackState,
            fallbackCopy: copy.subtitle,
            appName: appName
        )

        // A nil blur style makes iOS ignore backgroundColor and paint its own
        // near-black scrim — the light material is what actually carries the
        // paper tone (and holds it even on dark-mode devices).
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialLight,
            backgroundColor: background,
            icon: shieldArtwork(),
            title: ShieldConfiguration.Label(text: copy.title, color: titleColor),
            subtitle: ShieldConfiguration.Label(text: subtitle, color: subtitleColor),
            primaryButtonLabel: ShieldConfiguration.Label(text: shieldPrimaryButtonTitle(fallbackState: fallbackState), color: buttonInk),
            primaryButtonBackgroundColor: buttonGold,
            secondaryButtonLabel: ShieldConfiguration.Label(text: copy.secondaryButton, color: subtitleColor)
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
            return "Didn't receive the notification? Try again"
        case .notificationsDisabled:
            return "Write ⊙"
        }
    }

    private func shieldArtwork() -> UIImage? {
        Self.cachedArtwork
    }

    // Shield extensions run under a ~6 MB memory ceiling; decoding the icon at
    // full asset resolution gets the process jetsammed and iOS falls back to
    // the default "Restricted" shield. Decode once, straight to display size.
    private static let cachedArtwork: UIImage? = {
        let bundle = Bundle(for: ShieldConfigurationExtension.self)
        guard let url = bundle.url(forResource: "anky_shield_door_icon", withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        // Fixed 3x: UITraitCollection.current can be unspecified during extension
        // static init, and a 3x decode stays sharp on every device at ~350 KB.
        let scale: CGFloat = 3
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(artworkPointSize * scale)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }()

    private static let artworkPointSize: CGFloat = 100
}
