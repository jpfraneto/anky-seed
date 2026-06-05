import SwiftUI
import UIKit

enum AnkyTheme {
    static let background = Color(red: 0.031, green: 0.035, blue: 0.043)
    static let panel = Color(red: 0.063, green: 0.075, blue: 0.094)
    static let panelStrong = Color(red: 0.082, green: 0.098, blue: 0.133)
    static let border = Color(red: 0.149, green: 0.169, blue: 0.208)
    static let gold = Color(red: 0.843, green: 0.729, blue: 0.451)
    static let goldBright = Color(red: 0.949, green: 0.827, blue: 0.573)
    static let text = Color(red: 0.957, green: 0.945, blue: 0.918)
    static let textMuted = Color(red: 0.612, green: 0.639, blue: 0.686)
    static let success = Color(red: 0.525, green: 0.937, blue: 0.675)
    static let danger = Color(red: 0.973, green: 0.443, blue: 0.443)
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
}
