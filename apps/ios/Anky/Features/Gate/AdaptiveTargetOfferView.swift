import SwiftUI

/// Phase-2 §1: after two consecutive missed days, one gentle offer to walk
/// with a smaller target for a while. Pastel register, Anky present, exactly
/// two choices — never a badge, never a nag, never shown twice per episode.
struct AdaptiveTargetOfferView: View {
    let offer: AdaptiveTargetOffer
    let onLower: () -> Void
    let onKeep: () -> Void

    var body: some View {
        ZStack {
            Color.ankyPaper.ignoresSafeArea()
            LazureWall(mood: .dawn).ignoresSafeArea()
            WatercolorVeilView(register: .pale).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                AnkySpriteView(sequence: .shyListening, size: 132)

                Text(AnkyLocalization.ui(AnkyCopyRegistry.adaptiveOfferLine(
                    targetMinutes: offer.currentTargetMinutes,
                    suggestedMinutes: offer.suggestedTargetMinutes
                )))
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

                Spacer()

                VStack(spacing: 14) {
                    Button(action: onLower) {
                        Text(AnkyLocalization.ui(AnkyCopyRegistry.adaptiveOfferLower(
                            suggestedMinutes: offer.suggestedTargetMinutes
                        )))
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(Color.ankyGoldLight.opacity(0.42)))
                    }

                    Button(action: onKeep) {
                        Text(AnkyLocalization.ui(AnkyCopyRegistry.adaptiveOfferKeep(
                            targetMinutes: offer.currentTargetMinutes
                        )))
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().stroke(Color.ankyInkSoft.opacity(0.28), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 56)
            }
        }
    }
}
