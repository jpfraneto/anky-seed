import SwiftUI

/// The frame-position invariant.
///
/// The painting's frame occupies the IDENTICAL position and size on the
/// ceremony screen and the main screen — it never moves during the
/// ceremony → main transition; everything else changes around it. Both
/// surfaces must lay the frame out through this one type.
enum PaintingFrameMetrics {
    /// Horizontal inset from the screen edge to the frame.
    static let horizontalInset: CGFloat = 28
    /// The frame's top edge, as a fraction of the container height.
    static let topFraction: CGFloat = 0.14
    /// Widest the painting ever renders (iPad, landscape).
    static let maxSide: CGFloat = 420
    /// The whisper-thin gold border around the canvas.
    static let borderWidth: CGFloat = 1.5
    /// Outer glow radius that "stains" the background around the frame.
    static let glowRadius: CGFloat = 42

    /// The square canvas rect for a given container size. Identical math on
    /// every surface that shows the framed painting.
    static func frameRect(in containerSize: CGSize) -> CGRect {
        let side = min(containerSize.width - horizontalInset * 2, maxSide)
        let x = (containerSize.width - side) / 2
        let y = containerSize.height * topFraction
        return CGRect(x: x, y: y, width: side, height: side)
    }
}

/// The main screen's painting lives inside a scroll view under a header, so
/// its measured position — not frameRect's idealized math — is the truth the
/// ceremony must hold. The home surface reports the live global rect here;
/// the ceremony (full-screen, so local == global) reads it back.
@MainActor
enum PaintingFramePosition {
    static var lastHomeGlobalRect: CGRect?
}
