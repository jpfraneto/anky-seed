import SwiftUI

/// The reusable framed painting: whisper-thin gold frame, palette-tinted
/// glow staining the wall behind it, and the reveal composite inside.
///
/// Used by the main screen, the post-session strokes beat, the ceremony,
/// and the gallery. Progress is animatable; the lantern is lit at any value.
struct PaintingView: View {
    let assets: PaintingRevealAssets
    var progress: Double
    var glowTint: Color = .ankyGold
    var glowStrength: Double = 1

    var body: some View {
        PaintingRevealCanvas(assets: assets, progress: progress)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.ankyGoldLight, .ankyGold, .ankyGoldLight.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: PaintingFrameMetrics.borderWidth
                    )
            )
            .shadow(
                color: glowTint.opacity(0.32 * glowStrength),
                radius: PaintingFrameMetrics.glowRadius,
                x: 0,
                y: 6
            )
            .shadow(
                color: glowTint.opacity(0.18 * glowStrength),
                radius: PaintingFrameMetrics.glowRadius * 2.2,
                x: 0,
                y: 0
            )
    }
}
