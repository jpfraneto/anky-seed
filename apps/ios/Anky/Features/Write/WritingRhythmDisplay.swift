import SwiftUI
import UIKit

/// The sentinel's shared visual language, compiled into both the app and the
/// App Clip so the silence treatment can never drift between them.
enum WritingRhythmColor {
    // Umber on parchment (phase-2 §7 sepia pass) — matches Color.ankyUmber.
    private static let ink = (red: 0.310, green: 0.243, blue: 0.180)
    private static let madder = (red: 0.702, green: 0.325, blue: 0.302)

    static func color(progress: Double, colorScheme: ColorScheme = .dark) -> Color {
        let clamped = min(1, max(0, progress))
        let red = ink.red + (madder.red - ink.red) * clamped
        let green = ink.green + (madder.green - ink.green) * clamped
        let blue = ink.blue + (madder.blue - ink.blue) * clamped
        return Color(.displayP3, red: red, green: green, blue: blue)
    }

    static func uiColor(progress: Double, alpha: Double = 1, colorScheme: ColorScheme = .dark) -> UIColor {
        UIColor(color(progress: progress, colorScheme: colorScheme)).withAlphaComponent(alpha)
    }
}

/// A whisper of a line above the keyboard: full when a key just landed,
/// draining right to left through the configured terminal stillness.
struct SilenceLifeBar: View {
    let remaining: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.ankyInk.opacity(0.05))
                Capsule()
                    .fill(Color.ankyUmber.opacity(0.34))
                    .frame(width: max(0, geometry.size.width * min(1, max(0, remaining))))
            }
        }
    }
}
