import SwiftUI

// MARK: - Card layers

/// Which painted Anky sits on the card. One pose today; a new pose is one case
/// plus one asset — do not add cases speculatively.
enum AnkyPose {
    case seated

    var assetName: String {
        switch self {
        case .seated: return "ShareCardAnky_Seated"
        }
    }
}

/// Which watercolor plate the card is painted on. One plate today.
enum BackgroundPlate {
    case goldenGround

    var assetName: String {
        switch self {
        case .goldenGround: return "ShareCardPlate_GoldenGround"
        }
    }
}

// MARK: - The card

/// The 9:16 share card, layered: a static watercolor plate, a static painted
/// Anky, and the quote live-set in Fraunces (never baked into an asset, so any
/// quote stays crisp). Designed at export pixels — 1080×1920 — and rasterized
/// at scale 1, so the preview is exactly what exports.
///
/// The quote centers in the flexible field above Anky; the spacer between them
/// is a hard minimum, so a long quote scales down before it can ever touch the
/// figure, and a short quote floats high in the golden field instead of
/// sinking toward him.
struct ShareCardView: View {
    static let designSize = CGSize(width: 1080, height: 1920)

    /// Already card-safe — run through `QuoteSanitizer.prepareForCard` upstream.
    let quote: String
    var voice: ShareCardVoice = .anky
    var pose: AnkyPose = .seated
    var plate: BackgroundPlate = .goldenGround

    /// Starting quote size; steps down with length before auto-scaling engages.
    private var startFontSize: CGFloat {
        switch quote.count {
        case ..<90:   return 90
        case ..<170:  return 78
        case ..<260:  return 66
        default:      return 57
        }
    }

    var body: some View {
        ZStack {
            plateLayer

            VStack(spacing: 0) {
                VStack(spacing: 40) {
                    quoteText
                    attribution
                }
                .padding(.horizontal, 90)
                .padding(.top, 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 72)

                characterLayer
                    .frame(height: 560)
                    .padding(.bottom, 26)

                lockup
                    .padding(.bottom, 70)
            }
        }
        .frame(width: Self.designSize.width, height: Self.designSize.height)
        .clipped()
        // The card is a fixed canvas; Dynamic Type must not move the layout.
        .dynamicTypeSize(.large)
    }

    private var quoteText: some View {
        Text("\u{201C}\(quote)\u{201D}")
            .font(.fraunces(startFontSize, weight: .regular))
            .foregroundStyle(Color.ankyQuoteInk)
            .lineSpacing(startFontSize * 0.28)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
    }

    private var attribution: some View {
        Text(voice.attribution)
            .font(.fraunces(34, weight: .semibold, italic: true))
            .tracking(4)
            .foregroundStyle(Color.ankyGold)
    }

    private var lockup: some View {
        VStack(spacing: 10) {
            Text("anky")
                .font(.fraunces(40, weight: .semibold))
            Text("anky.app")
                .font(.fraunces(22, weight: .regular))
                .tracking(2)
        }
        .foregroundStyle(Color.ankyQuoteInk.opacity(0.85))
    }

    @ViewBuilder
    private var plateLayer: some View {
        if let image = UIImage(named: plate.assetName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.designSize.width, height: Self.designSize.height)
        } else {
            // Lazure placeholder until the plate asset lands.
            LinearGradient(
                colors: [
                    Color.ankyViolet.opacity(0.32),
                    Color.ankyGoldLight.opacity(0.5),
                    Color.ankyViolet.opacity(0.4)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var characterLayer: some View {
        if let image = UIImage(named: pose.assetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            // Keep the layout stable until the character asset lands.
            Color.clear
        }
    }
}

// MARK: - Previews

#Preview("Long quote") {
    ShareCardView(
        quote: "You keep circling the same doorway, describing the wood grain in exquisite detail, as if naming the door enough times will open it. But the handle has been warm this whole time. What you call preparation is a very sophisticated way of standing still.",
        voice: .anky
    )
}

#Preview("Short quote") {
    ShareCardView(
        quote: "The handle has been warm this whole time.",
        voice: .you
    )
}
