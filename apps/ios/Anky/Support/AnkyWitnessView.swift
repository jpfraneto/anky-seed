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

enum AnkyCompanionPromptState {
    case importedReady
    case mirrorLoading
    case mirrorReady
    case notice
    case error

    var defaultMessage: String {
        switch self {
        case .importedReady:
            return "I found the rhythm inside this. Mirror it?"
        case .mirrorLoading:
            return "stay close.\ni’m listening for the shape underneath."
        case .mirrorReady:
            return "Something came back."
        case .notice:
            return "I am here."
        case .error:
            return "I could not find a .anky rhythm in that."
        }
    }

    fileprivate var mood: AnkyWitnessView.Mood {
        switch self {
        case .error:
            return .listening
        case .mirrorReady, .importedReady, .notice:
            return .warm
        case .mirrorLoading:
            return .quiet
        }
    }

    fileprivate var sequence: AnkySequenceName {
        switch self {
        case .importedReady:
            return .waveFront
        case .mirrorReady:
            return .celebrate
        case .mirrorLoading:
            return .shyListening
        case .notice:
            return .idleBlink
        case .error:
            return .softConcern
        }
    }
}

struct AnkyCompanionPromptView: View {
    let state: AnkyCompanionPromptState
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @State private var appeared = false

    init(
        state: AnkyCompanionPromptState,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.state = state
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AnkyWitnessView(mood: state.mood, size: .companion, sequence: state.sequence)
                .frame(width: 82, height: 82)
                .offset(x: appeared ? 0 : 18)
                .opacity(appeared ? 1 : 0)

            AnkyDialoguePanel(
                message: message ?? state.defaultMessage,
                actionTitle: actionTitle,
                action: action
            )
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AnkyConversationPromptView: View {
    let message: String
    let currentIndex: Int
    let totalCount: Int
    let next: () -> Void
    let close: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                Button(action: next) {
                    AnkyDialoguePanel(message: message)
                }
                .buttonStyle(.plain)

                HStack {
                    Spacer()

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AnkyTheme.gold.opacity(0.82))
                    .accessibilityLabel("Close Anky message")
                }
                .padding(.horizontal, 8)
                .padding(.top, 5)
            }

            HStack(spacing: 6) {
                ForEach(0..<totalCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == currentIndex ? AnkyTheme.gold.opacity(0.90) : AnkyTheme.gold.opacity(0.22))
                        .frame(width: 10, height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(AnkyTheme.gold.opacity(0.36), lineWidth: 1)
                        )
                }
            }
            .accessibilityLabel("Anky message \(currentIndex + 1) of \(totalCount)")
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AnkyDialoguePanel: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("anky")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(AnkyTheme.gold.opacity(0.82))

            Text(message.lowercased())
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .lineSpacing(5)
                .foregroundStyle(AnkyTheme.text.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle.lowercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(AnkyTheme.goldBright)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(AnkyTheme.gold.opacity(0.34), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dialogueBackground)
    }

    private var dialogueBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: 0.035, green: 0.049, blue: 0.082).opacity(0.94))
            .overlay(AnkyDialogueOrnaments())
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(AnkyTheme.gold.opacity(0.28), lineWidth: 1)
                    .padding(3)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 18, y: 10)
    }
}

private struct AnkyDialogueOrnaments: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let gold = AnkyTheme.gold.opacity(0.72)
                let dimGold = AnkyTheme.gold.opacity(0.24)
                let blue = Color.white.opacity(0.16)
                let inset: CGFloat = 7
                let corner: CGFloat = min(22, min(size.width, size.height) * 0.24)

                var corners = Path()
                corners.move(to: CGPoint(x: inset, y: inset + corner))
                corners.addLine(to: CGPoint(x: inset, y: inset))
                corners.addLine(to: CGPoint(x: inset + corner, y: inset))
                corners.move(to: CGPoint(x: size.width - inset - corner, y: inset))
                corners.addLine(to: CGPoint(x: size.width - inset, y: inset))
                corners.addLine(to: CGPoint(x: size.width - inset, y: inset + corner))
                corners.move(to: CGPoint(x: inset, y: size.height - inset - corner))
                corners.addLine(to: CGPoint(x: inset, y: size.height - inset))
                corners.addLine(to: CGPoint(x: inset + corner, y: size.height - inset))
                corners.move(to: CGPoint(x: size.width - inset - corner, y: size.height - inset))
                corners.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
                corners.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - corner))

                context.stroke(
                    corners,
                    with: .color(gold),
                    style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter)
                )

                let availableWidth = max(0, size.width - 72)
                let ticks = max(2, Int(availableWidth / 34))
                for index in 0..<ticks {
                    let progress = ticks == 1 ? 0.5 : CGFloat(index) / CGFloat(ticks - 1)
                    let x = 36 + progress * availableWidth
                    drawDiamond(in: &context, center: CGPoint(x: x, y: inset), radius: 2.8, color: dimGold)
                    drawDiamond(in: &context, center: CGPoint(x: x, y: size.height - inset), radius: 2.8, color: dimGold)
                }

                var horizontalThread = Path()
                horizontalThread.move(to: CGPoint(x: 34, y: 4))
                horizontalThread.addLine(to: CGPoint(x: size.width - 34, y: 4))
                horizontalThread.move(to: CGPoint(x: 34, y: size.height - 4))
                horizontalThread.addLine(to: CGPoint(x: size.width - 34, y: size.height - 4))
                context.stroke(horizontalThread, with: .color(blue), style: StrokeStyle(lineWidth: 1))
            }
            .allowsHitTesting(false)
        }
    }

    private func drawDiamond(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        context.fill(path, with: .color(color))
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
