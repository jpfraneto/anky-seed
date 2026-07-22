import UIKit

/// Clip-target stand-ins for two app types `AnkyLazure.swift` touches.
///
/// The clip compiles the lazure design system as-is so the surface can never
/// drift from the app; these fill the two references whose real homes the
/// clip must not carry:
/// - `AnkyHaptics` lives in `AnkyTheme.swift` (drags further app UI) — the
///   haptic surface is reproduced verbatim.
/// - `AnkyFunnel` lives in `LevelSyncClient.swift` (networking + identity).
///   The clip sends nothing anywhere, so reporting is a no-op by design.
enum AnkyHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum AnkyFunnel {
    static let veilTapped = "veil_tapped"

    static func report(_ event: String, origin: String? = nil) {
        // No networking in the clip. Nothing leaves the device.
    }
}
