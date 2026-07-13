import SwiftUI
import UIKit

/// Legacy token names, now resolved to the lazure pigments
/// (see AnkyLazure.swift). The app is painted on warm paper with
/// violet ink — no pure white, no pure black, no hard edges.
enum AnkyTheme {
    static let background = Color.ankyPaper
    static let panel = Color.ankyPaperDeep.opacity(0.62)
    static let panelStrong = Color.ankyPaperDeep
    static let border = Color.ankyInk.opacity(0.10)
    static let gold = Color.ankyGold
    static let goldBright = Color.ankyGoldLight
    static let text = Color.ankyInk
    static let textMuted = Color.ankyInkSoft
    static let success = Color.ankySage
    static let danger = Color.ankyMadder
}

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
