import SwiftUI

/// The small material vocabulary of the writing machine. Only the edge shading
/// of the display survives the simplification pass (2026-08-17): the wooden
/// puck, dial, and keyboard dock are gone — the page is the object now.
enum GeshtuWoodPalette {
    static let detail = Color(.displayP3, red: 0.29, green: 0.24, blue: 0.21)
}

/// The luminous display is the low point in the object. Soft side falloff and
/// a shallow upper recess establish depth without drawing a card around the page.
struct GeshtuWritingSurface: View {
    let progress: Double

    var body: some View {
        let settledLight = min(1, max(0, progress))

        ZStack {
            Color.ankyPaper

            // A warm display, not a moving illustration. Over the ritual the
            // rose settles almost imperceptibly toward cream, once per minute.
            LinearGradient(
                colors: [
                    Color.ankyPaper,
                    Color.ankyRose.opacity(0.15 - settledLight * 0.04),
                    Color.ankyPaperDeep.opacity(0.46)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.20 + settledLight * 0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.78, y: 0.14),
                startRadius: 0,
                endRadius: 410
            )

            RadialGradient(
                colors: [Color.ankyRose.opacity(0.075), .clear],
                center: UnitPoint(x: 0.18, y: 0.82),
                startRadius: 0,
                endRadius: 480
            )

            PaperGrain()
                .opacity(0.32)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [GeshtuWoodPalette.detail.opacity(0.085), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 7)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [.clear, GeshtuWoodPalette.detail.opacity(0.075)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 7)
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [GeshtuWoodPalette.detail.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 11)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
