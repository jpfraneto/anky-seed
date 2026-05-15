import SwiftUI

struct AnkyWitnessView: View {
    enum Mood {
        case listening
        case quiet
        case warm
    }

    enum Size {
        case companion
        case tiny
        case small
        case sheet

        var glyph: CGFloat {
            switch self {
            case .companion:
                return 66
            case .tiny:
                return 20
            case .small:
                return 30
            case .sheet:
                return 42
            }
        }

        var padding: CGFloat {
            switch self {
            case .companion:
                return 8
            case .tiny:
                return 5
            case .small:
                return 7
            case .sheet:
                return 9
            }
        }
    }

    let mood: Mood
    let size: Size
    let sequence: AnkySequenceName
    @State private var breathing = false

    init(mood: Mood = .quiet, size: Size = .small, sequence: AnkySequenceName = .idleFront) {
        self.mood = mood
        self.size = size
        self.sequence = sequence
    }

    var body: some View {
        ZStack {
            if size == .companion {
                AnkySpriteView(sequence: sequence, size: size.glyph)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.78))

                Circle()
                    .stroke(borderColor.opacity(0.9), lineWidth: 1)

                AnkyGlyphView()
                    .frame(width: size.glyph, height: size.glyph)
                    .foregroundStyle(borderColor)
                    .padding(size.padding)
            }
        }
        .frame(width: size.glyph + size.padding * 2, height: size.glyph + size.padding * 2)
        .scaleEffect(breathing ? 1.035 : 0.985)
        .opacity(mood == .listening ? 0.72 : 0.92)
        .animation(
            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
            value: breathing
        )
        .onAppear {
            breathing = true
        }
        .accessibilityLabel("Anky witness")
    }

    private var borderColor: Color {
        switch mood {
        case .listening:
            return .cyan
        case .quiet:
            return AnkyTheme.border
        case .warm:
            return AnkyTheme.gold
        }
    }
}

private struct AnkyGlyphView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.34

        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))

        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.08))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.18))
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.18))

        return path
    }
}
