import SwiftUI
import UIKit

/// Rasterizes the share card at exactly export size — the view is designed in
/// pixels (1080×1920), so scale stays 1. Main-actor because `ImageRenderer`
/// is. Only the share flow calls this, and sharing exists post-session, so it
/// never competes with the writing screen's ticker for the main actor.
enum ShareCardRenderer {
    @MainActor
    static func render(
        quote: String,
        voice: ShareCardVoice = .anky,
        pose: AnkyPose = .seated,
        plate: BackgroundPlate = .goldenGround
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: ShareCardView(quote: quote, voice: voice, pose: pose, plate: plate)
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(ShareCardView.designSize)
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
