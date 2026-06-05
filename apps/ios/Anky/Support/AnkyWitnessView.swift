import SwiftUI
import UIKit

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

enum AnkyCompanionMood {
    case idle
    case listening
    case thinking
    case celebrating
    case concerned
    case guiding

    var witnessMood: AnkyWitnessView.Mood {
        switch self {
        case .idle, .thinking, .guiding:
            return .quiet
        case .listening, .concerned:
            return .listening
        case .celebrating:
            return .warm
        }
    }

    var sequence: AnkySequenceName {
        switch self {
        case .idle:
            return .idleBlink
        case .listening:
            return .shyListening
        case .thinking:
            return .shyListening
        case .celebrating:
            return .celebrate
        case .concerned:
            return .softConcern
        case .guiding:
            return .waveFront
        }
    }
}

struct AnkyBubbleStep: Identifiable {
    let id = UUID()
    let text: String

    init(_ text: String) {
        self.text = text
    }
}

struct AnkyBubble: Identifiable {
    let id = UUID()
    let text: String
    let actions: [AnkyChatAction]
    let steps: [AnkyBubbleStep]
    let isThinking: Bool
    let close: (() -> Void)?

    init(
        text: String,
        actions: [AnkyChatAction] = [],
        steps: [AnkyBubbleStep] = [],
        isThinking: Bool = false,
        close: (() -> Void)? = nil
    ) {
        self.text = text
        self.actions = Array(actions.prefix(4))
        self.steps = steps
        self.isThinking = isThinking
        self.close = close
    }
}

@MainActor
final class AnkyCompanionStore: ObservableObject {
    @Published private(set) var mood: AnkyCompanionMood = .idle
    @Published private(set) var bubble: AnkyBubble?
    @Published private(set) var sequenceOverride: AnkySequenceName?

    func witness(
        mood: AnkyCompanionMood,
        sequence: AnkySequenceName? = nil,
        bubble: AnkyBubble? = nil
    ) {
        withAnimation(.easeOut(duration: 0.22)) {
            self.mood = mood
            self.sequenceOverride = sequence
            self.bubble = bubble
        }
    }

    func hideBubble(returningTo mood: AnkyCompanionMood = .idle) {
        withAnimation(.easeOut(duration: 0.18)) {
            bubble = nil
            self.mood = mood
            sequenceOverride = nil
        }
    }
}

struct AnkyChatAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let badge: String?
    let isPrimary: Bool
    let preservesCase: Bool
    let action: () -> Void

    init(
        _ title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        isPrimary: Bool = false,
        preservesCase: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = [title, subtitle, badge].compactMap(\.self).joined(separator: "-")
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.isPrimary = isPrimary
        self.preservesCase = preservesCase
        self.action = action
    }
}

struct AnkyCompanionPromptView: View {
    let state: AnkyCompanionPromptState
    let message: String?
    let actions: [AnkyChatAction]
    let showsWitness: Bool

    @State private var appeared = false

    init(
        state: AnkyCompanionPromptState,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        actions: [AnkyChatAction]? = nil,
        showsWitness: Bool = false
    ) {
        self.state = state
        self.message = message
        if let actions {
            self.actions = Array(actions.prefix(4))
        } else if let actionTitle, let action {
            self.actions = [AnkyChatAction(actionTitle, isPrimary: true, action: action)]
        } else {
            self.actions = []
        }
        self.showsWitness = showsWitness
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsWitness {
                AnkyWitnessView(mood: state.mood, size: .companion, sequence: state.sequence)
                    .frame(width: 82, height: 82)
                    .offset(x: appeared ? 0 : 18)
                    .opacity(appeared ? 1 : 0)
            }

            AnkyDialoguePanel(
                message: message ?? state.defaultMessage,
                actions: actions,
                isThinking: state == .mirrorLoading
            )
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                appeared = true
            }
        }
        .overlay {
            if state == .mirrorLoading {
                AnkyThinkingHaptics()
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AnkyConversationPromptView: View {
    let message: String
    let actions: [AnkyChatAction]
    let isThinking: Bool
    let close: () -> Void

    @State private var appeared = false

    init(
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        actions: [AnkyChatAction]? = nil,
        isThinking: Bool = false,
        close: @escaping () -> Void
    ) {
        self.message = message
        self.isThinking = isThinking
        if let actions {
            self.actions = Array(actions.prefix(4))
        } else if let actionTitle, let action {
            self.actions = [AnkyChatAction(actionTitle, isPrimary: true, action: action)]
        } else {
            self.actions = []
        }
        self.close = close
    }

    var body: some View {
        ZStack(alignment: .top) {
            AnkyDialoguePanel(
                message: message,
                actions: actions,
                isThinking: isThinking
            )

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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) {
                appeared = true
            }
        }
        .overlay {
            if isThinking {
                AnkyThinkingHaptics()
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AnkyBubbleView: View {
    let bubble: AnkyBubble
    let close: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .top) {
            AnkyDialoguePanel(
                message: bubble.text,
                actions: bubble.actions,
                steps: bubble.steps,
                isThinking: bubble.isThinking
            )

            HStack {
                Spacer()

                Button {
                    if let bubbleClose = bubble.close {
                        bubbleClose()
                    } else {
                        close()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AnkyTheme.gold.opacity(0.82))
                .accessibilityLabel("Close Anky bubble")
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) {
                appeared = true
            }
        }
        .overlay {
            if bubble.isThinking {
                AnkyThinkingHaptics()
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AnkyDialoguePanel: View {
    let message: String
    var actions: [AnkyChatAction]
    let steps: [AnkyBubbleStep]
    let isThinking: Bool

    init(
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        actions: [AnkyChatAction] = [],
        steps: [AnkyBubbleStep] = [],
        isThinking: Bool = false
    ) {
        self.message = message
        self.steps = steps
        self.isThinking = isThinking
        if !actions.isEmpty {
            self.actions = Array(actions.prefix(4))
        } else if let actionTitle, let action {
            self.actions = [AnkyChatAction(actionTitle, isPrimary: true, action: action)]
        } else {
            self.actions = []
        }
    }

    var body: some View {
        let hasMessage = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isActionOnly = !hasMessage && steps.isEmpty && !isThinking

        VStack(alignment: .leading, spacing: 10) {
            if hasMessage || isThinking {
                HStack(spacing: 8) {
                    Text("anky")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(AnkyTheme.gold.opacity(0.82))

                    if isThinking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .tint(AnkyTheme.goldBright)
                            .frame(width: 14, height: 14)
                            .accessibilityLabel("Anky is thinking")
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))

                        AnkyThinkingGlyph()
                            .frame(width: 28, height: 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }
                }
            }

            if hasMessage {
                Text(message)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .lineSpacing(5)
                    .foregroundStyle(AnkyTheme.text.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        Text("\(index + 1). \(step.text)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineSpacing(3)
                            .foregroundStyle(AnkyTheme.goldBright.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
            }

            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { chatAction in
                        Button(action: chatAction.action) {
                            VStack(spacing: 2) {
                                if let badge = chatAction.badge {
                                    Text(displayText(badge, preservesCase: chatAction.preservesCase))
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .tracking(0.35)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }

                                Text(displayText(chatAction.title, preservesCase: chatAction.preservesCase))
                                    .font(.system(size: isActionOnly ? 15 : 12, weight: .bold, design: .monospaced))
                                    .tracking(0.35)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)

                                if let subtitle = chatAction.subtitle {
                                    Text(displayText(subtitle, preservesCase: chatAction.preservesCase))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .tracking(0.25)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                                .foregroundStyle(chatAction.isPrimary ? Color.black.opacity(0.88) : AnkyTheme.goldBright)
                                .padding(.horizontal, isActionOnly ? 14 : 8)
                                .frame(maxWidth: .infinity)
                                .frame(height: isActionOnly ? 58 : (chatAction.subtitle == nil && chatAction.badge == nil ? 32 : 58))
                                .background(
                                    chatAction.isPrimary ? AnkyTheme.goldBright : Color.black.opacity(0.22),
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(chatAction.isPrimary ? Color.white.opacity(0.46) : AnkyTheme.gold.opacity(0.34), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dialogueBackground)
        .animation(.easeInOut(duration: 0.20), value: isThinking)
    }

    private func displayText(_ text: String, preservesCase: Bool) -> String {
        text
    }

    private var dialogueBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: 0.035, green: 0.049, blue: 0.082).opacity(0.94))
            .overlay(AnkyDialogueOrnaments())
            .overlay {
                if isThinking {
                    AnkyThinkingCurrent()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isThinking ? AnkyTheme.gold.opacity(0.78) : Color.white.opacity(0.70), lineWidth: 1)
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

private struct AnkyThinkingGlyph: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(time * 2.8) + 1) / 2
            let flow = CGFloat(phase)

            Canvas { context, size in
                let stroke = AnkyTheme.gold.opacity(0.82)
                let sand = AnkyTheme.goldBright.opacity(0.92)
                let centerX = size.width / 2
                let inset: CGFloat = 2
                let topY = inset
                let midY = size.height / 2
                let bottomY = size.height - inset

                var glass = Path()
                glass.move(to: CGPoint(x: inset, y: topY))
                glass.addLine(to: CGPoint(x: size.width - inset, y: topY))
                glass.addLine(to: CGPoint(x: centerX + 1.5, y: midY))
                glass.addLine(to: CGPoint(x: size.width - inset, y: bottomY))
                glass.addLine(to: CGPoint(x: inset, y: bottomY))
                glass.addLine(to: CGPoint(x: centerX - 1.5, y: midY))
                glass.closeSubpath()
                context.stroke(glass, with: .color(stroke), lineWidth: 1)

                var topSand = Path()
                topSand.move(to: CGPoint(x: inset + 5, y: topY + 3))
                topSand.addLine(to: CGPoint(x: size.width - inset - 5, y: topY + 3))
                topSand.addLine(to: CGPoint(x: centerX, y: midY - 2 - flow * 3))
                topSand.closeSubpath()
                context.fill(topSand, with: .color(sand.opacity(0.72 - Double(flow) * 0.42)))

                var bottomSand = Path()
                bottomSand.move(to: CGPoint(x: centerX, y: midY + 2 + flow * 3))
                bottomSand.addLine(to: CGPoint(x: size.width - inset - 5, y: bottomY - 3))
                bottomSand.addLine(to: CGPoint(x: inset + 5, y: bottomY - 3))
                bottomSand.closeSubpath()
                context.fill(bottomSand, with: .color(sand.opacity(0.38 + Double(flow) * 0.44)))

                let dropY = midY - 3 + flow * 8
                context.fill(
                    Path(ellipseIn: CGRect(x: centerX - 1.1, y: dropY, width: 2.2, height: 2.2)),
                    with: .color(sand)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AnkyThinkingCurrent: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let lineCount = 5
                for index in 0..<lineCount {
                    let phase = time * 0.42 + Double(index) * 0.9
                    let x = size.width * CGFloat((sin(phase) + 1) / 2)
                    let opacity = 0.035 + 0.030 * ((sin(phase * 1.7) + 1) / 2)
                    var path = Path()
                    path.move(to: CGPoint(x: x - size.width * 0.18, y: 0))
                    path.addLine(to: CGPoint(x: x + size.width * 0.10, y: size.height))
                    context.stroke(
                        path,
                        with: .color(AnkyTheme.gold.opacity(opacity)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                }
            }
        }
    }
}

private struct AnkyThinkingHaptics: View {
    @State private var pulseTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .onAppear {
                pulseTask?.cancel()
                pulseTask = Task { @MainActor in
                    let generator = UIImpactFeedbackGenerator(style: .soft)
                    generator.prepare()
                    while !Task.isCancelled {
                        generator.impactOccurred(intensity: 0.32)
                        generator.prepare()
                        try? await Task.sleep(nanoseconds: 1_350_000_000)
                    }
                }
            }
            .onDisappear {
                pulseTask?.cancel()
                pulseTask = nil
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
