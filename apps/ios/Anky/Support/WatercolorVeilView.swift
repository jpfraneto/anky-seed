import SwiftUI

/// The Waldorf/Steiner loading state: soft watercolor veils breathing and
/// blooming across parchment. No spinner, ever. Built once, reused for the
/// reflection wait and the painting-generation wait.
struct WatercolorVeilView: View {
    var message: String?
    /// Dark mode for the ceremony's aubergine register.
    var register: Register = .pale

    enum Register {
        case pale // gate / reflection loading: pale morning pastel
        case aubergine // ceremony waiting: candlelit darkness, never black

        var veilColors: [Color] {
            switch self {
            case .pale:
                return [.ankyRose, .ankyViolet, .ankyGoldLight, .ankyApricot]
            case .aubergine:
                return [.ankyViolet, .ankyMadder, .ankyGold, .ankyRose]
            }
        }

        var textColor: Color {
            switch self {
            case .pale: return .ankyInkSoft
            case .aubergine: return .ankyPaperDeep.opacity(0.85)
            }
        }
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = AnkyBreath.phase(at: timeline.date)
                Canvas { context, size in
                    let colors = register.veilColors
                    for (index, color) in colors.enumerated() {
                        let seed = Double(index)
                        let breathe = 0.5 + 0.5 * sin(phase * 2 * .pi + seed * 1.7)
                        let x = size.width * (0.22 + 0.56 * fract(seed * 0.37 + phase * 0.05))
                        let y = size.height * (0.25 + 0.5 * fract(seed * 0.61 - phase * 0.03))
                        let radius = size.width * (0.34 + 0.18 * breathe)
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(
                            Ellipse().path(in: rect),
                            with: .radialGradient(
                                Gradient(colors: [
                                    color.opacity(0.16 + 0.10 * breathe),
                                    color.opacity(0),
                                ]),
                                center: CGPoint(x: x, y: y),
                                startRadius: 0,
                                endRadius: radius
                            )
                        )
                    }
                }
            }

            if let message {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(register.textColor)
                        .padding(.bottom, 64)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
