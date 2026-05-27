import SwiftUI
import UIKit

struct RevealView: View {
    @StateObject private var viewModel: RevealViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ankyCompanion: AnkyCompanionStore
    @State private var confirmDelete = false
    @State private var copiedSection: RevealCopySection?
    @State private var copyBurst: RevealCopyBurst?
    private let onDeleted: () -> Void
    private let onTryAgain: () -> Void
    private let onOpenCredits: () -> Void

    init(
        viewModel: RevealViewModel,
        onDeleted: @escaping () -> Void = {},
        onTryAgain: @escaping () -> Void = {},
        onOpenCredits: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDeleted = onDeleted
        self.onTryAgain = onTryAgain
        self.onOpenCredits = onOpenCredits
    }

    var body: some View {
        ZStack {
            RevealPalette.ink
                .ignoresSafeArea()

            RevealBackgroundTexture()

            VStack(spacing: 0) {
                RevealHeader(
                    date: viewModel.createdDate,
                    time: viewModel.createdTime,
                    metadata: viewModel.metadataLine,
                    isDeleting: viewModel.isDeleting,
                    dismiss: dismiss,
                    delete: {
                        RevealHaptics.warning()
                        confirmDelete = true
                    }
                )

                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            SelectableWritingText(
                                text: viewModel.reconstructedText,
                                isHighlighted: copiedSection == .writing,
                                onTap: copyWriting
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .id(RevealScrollTarget.writing)

                            PrivacyDivider()
                                .padding(.top, 34)

                            if let reflection = viewModel.reflection {
                                SavedReflectionPanel(
                                    reflection: reflection,
                                    isHighlighted: copiedSection == .reflection,
                                    onTap: copyReflection
                                )
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, viewModel.reflection == nil ? 238 : 72)
                    }
                    .onChange(of: viewModel.reflection?.id) { _, reflectionID in
                        guard reflectionID != nil else {
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            withAnimation(.easeInOut(duration: 0.55)) {
                                scrollProxy.scrollTo(RevealScrollTarget.reflection, anchor: .top)
                            }
                        }
                    }
                }
            }

            if let copyBurst {
                RevealCopyEmojiBurst(burst: copyBurst)
                    .position(copyBurst.location)
                    .allowsHitTesting(false)
                    .zIndex(80)
            }
        }
        .coordinateSpace(name: "revealRoot")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("delete forever?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("delete forever", role: .destructive) {
                RevealHaptics.warning()
                viewModel.deleteSession()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this writing session and its saved reflection from this device. This cannot be undone.")
        }
        .onAppear {
            Task {
                await viewModel.refreshCredits(showError: false)
            }
            syncRevealBubble()
        }
        .onDisappear {
            ankyCompanion.hideBubble()
        }
        .onChange(of: viewModel.isDeleted) { _, isDeleted in
            guard isDeleted else {
                return
            }
            onDeleted()
            dismiss()
        }
        .onChange(of: viewModel.isAskingAnky) { _, _ in
            syncRevealBubble()
        }
        .onChange(of: viewModel.reflection?.id) { _, _ in
            syncRevealBubble()
        }
        .onChange(of: viewModel.reflectionStatusMessage) { _, _ in
            syncRevealBubble()
        }
        .onChange(of: viewModel.creditsLoading) { _, _ in
            syncRevealBubble()
        }
        .onChange(of: viewModel.creditPromptState) { _, _ in
            syncRevealBubble()
        }
        .onChange(of: viewModel.errorMessage) { _, _ in
            syncRevealBubble()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let isHorizontalBackSwipe = value.translation.width > 80
                        && value.startLocation.x < 32
                        && abs(value.translation.height) < 60
                    if isHorizontalBackSwipe {
                        dismiss()
                    }
                }
        )
    }

    private func syncRevealBubble() {
        guard viewModel.reflection == nil else {
            ankyCompanion.hideBubble()
            return
        }

        if viewModel.isAskingAnky {
            let status = viewModel.reflectionStatusMessage.isEmpty
                ? "i am staying with this .anky."
                : viewModel.reflectionStatusMessage
            ankyCompanion.witness(
                mood: .thinking,
                sequence: .shyListening,
                bubble: AnkyBubble(
                    text: "\(status)\n\ni am reading slowly. not looking for a summary.",
                    isThinking: true
                )
            )
            return
        }

        if !viewModel.isComplete {
            ankyCompanion.witness(
                mood: .guiding,
                sequence: .waveFront,
                bubble: AnkyBubble(
                    text: viewModel.shortSessionMessage,
                    actions: [
                        AnkyChatAction("write again", isPrimary: true) {
                            onTryAgain()
                        }
                    ]
                )
            )
            return
        }

        var actions: [AnkyChatAction] = []
        if viewModel.canSubmitReflectionRequest {
            actions.append(
                AnkyChatAction("reflect with anky", isPrimary: true) {
                    Task {
                        await viewModel.askAnky()
                    }
                }
            )
        }
        if viewModel.shouldShowCreditsLink {
            actions.append(
                AnkyChatAction("open credits") {
                    onOpenCredits()
                }
            )
        }

        let text = [reflectionInvitationMessage, viewModel.errorMessage]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        ankyCompanion.witness(
            mood: viewModel.errorMessage == nil ? .guiding : .concerned,
            sequence: viewModel.errorMessage == nil ? .waveFront : .softConcern,
            bubble: AnkyBubble(
                text: text,
                actions: actions,
                isThinking: viewModel.creditsLoading
            )
        )
    }

    private var reflectionInvitationMessage: String {
        if viewModel.creditsLoading {
            return "i am checking whether the mirror is open.\n\nyour writing stays here unless you ask me to reflect it."
        }

        switch viewModel.creditPromptState {
        case .available, .freeGift:
            return "i can sit with this and bring back a reflection.\n\nyour writing only leaves this device if you ask me now."
        case .unavailable:
            return "i want to reflect this with you, but reflection access is empty right now."
        case .unknown:
            return "the mirror may be open.\n\nyour writing only leaves this device if you ask me now."
        }
    }

    private func copyWriting(at location: CGPoint) {
        copy(.writing, at: location)
    }

    private func copyReflection(at location: CGPoint) {
        copy(.reflection, at: location)
    }

    private func copy(_ section: RevealCopySection, at location: CGPoint) {
        RevealHaptics.selection()
        viewModel.copy(section)
        let burst = RevealCopyBurst(location: location)
        withAnimation(.easeOut(duration: 0.08)) {
            copiedSection = section
            copyBurst = burst
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            guard copiedSection == section else {
                return
            }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedSection = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) {
            guard copyBurst?.id == burst.id else {
                return
            }
            withAnimation(.easeOut(duration: 0.18)) {
                copyBurst = nil
            }
        }
    }

}

private struct RevealCopyBurst: Identifiable, Equatable {
    let id = UUID()
    let location: CGPoint
}

private struct RevealCopyEmojiBurst: View {
    let burst: RevealCopyBurst

    var body: some View {
        Text("📋")
            .font(.system(size: 26))
            .padding(8)
            .background(RevealPalette.copyButtonFill.opacity(0.92), in: Circle())
            .overlay(
                Circle()
                    .stroke(RevealPalette.copyMagenta.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: RevealPalette.copyMagenta.opacity(0.45), radius: 14)
            .transition(.scale(scale: 0.62).combined(with: .opacity))
            .id(burst.id)
    }
}

private enum RevealHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func subtle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.42)
    }
}

private struct RevealHeader: View {
    let date: String
    let time: String
    let metadata: String
    let isDeleting: Bool
    let dismiss: DismissAction
    let delete: () -> Void

    private let backButtonSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RevealPalette.paper)
                    .frame(width: backButtonSize, height: backButtonSize)
                    .background(Color.black.opacity(0.24), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(RevealPalette.gold.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(spacing: 4) {
                Text("\(date) / \(time)".lowercased())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RevealPalette.paper.opacity(0.78))
                    .multilineTextAlignment(.center)

                Text(metadata.lowercased())
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(RevealPalette.paper.opacity(0.54))
            }
            .frame(maxWidth: .infinity)

            Button(action: delete) {
                if isDeleting {
                    ProgressView()
                        .tint(RevealPalette.paper)
                        .frame(width: backButtonSize, height: backButtonSize)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .frame(width: backButtonSize, height: backButtonSize)
                        .background(Color.black.opacity(0.24), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.22), lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityLabel("Delete writing session")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RevealPalette.ink.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RevealPalette.gold.opacity(0.13))
                .frame(height: 1)
        }
    }
}

private enum RevealScrollTarget {
    case writing
    case reflection
}

private struct RevealBackgroundTexture: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach([0.19, 0.47, 0.78], id: \.self) { position in
                    Rectangle()
                        .fill(RevealPalette.gold.opacity(0.075))
                        .frame(height: 1)
                        .offset(y: proxy.size.height * position)
                }

                Ellipse()
                    .fill(RevealPalette.violet.opacity(0.055))
                    .frame(width: proxy.size.width * 1.2, height: 280)
                    .blur(radius: 42)
                    .offset(y: proxy.size.height * 0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct PrivacyDivider: View {
    @State private var disclosure = PrivacyLockDisclosure()

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    disclosure.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(RevealPalette.gold.opacity(0.22))
                        .frame(height: 1)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(RevealPalette.goldSoft)
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.18), in: Circle())

                    Rectangle()
                        .fill(RevealPalette.gold.opacity(0.22))
                        .frame(height: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(disclosure.isExpanded ? "Hide privacy note" : "Show privacy note")

            if disclosure.isExpanded {
                Text("your writing only leaves this device if you ask for a reflection. the mirror processes it transiently and does not keep a writing archive.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(RevealPalette.paper.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct RevealAnkyReflectionChat: View {
    @ObservedObject var viewModel: RevealViewModel
    let tryAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isAskingAnky {
                RevealAnkyThinkingPrompt(status: viewModel.reflectionStatusMessage)
            } else if !viewModel.isComplete {
                AnkyCompanionPromptView(
                    state: .notice,
                    message: viewModel.shortSessionMessage,
                    actionTitle: "write again",
                    action: tryAgain
                )
            } else {
                AnkyCompanionPromptView(
                    state: .importedReady,
                    message: reflectionInvitationMessage,
                    actionTitle: viewModel.canSubmitReflectionRequest ? "reflect with anky" : nil,
                    action: {
                        Task {
                            await viewModel.askAnky()
                        }
                    }
                )
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage.lowercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(Color.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.shouldShowCreditsLink {
                NavigationLink {
                    CreditsPage(viewModel: YouViewModel())
                } label: {
                        Text("open reflection credits")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(RevealPalette.goldSoft)
                    }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reflectionInvitationMessage: String {
        if viewModel.creditsLoading {
            return "i am checking whether the mirror is open.\n\nyour writing stays here unless you ask me to reflect it."
        }

        switch viewModel.creditPromptState {
        case .available, .freeGift:
            return "i can sit with this and bring back a reflection.\n\nyour writing only leaves this device if you ask me now."
        case .unavailable:
            return "i want to reflect this with you, but reflection access is empty right now."
        case .unknown:
            return "the mirror may be open.\n\nyour writing only leaves this device if you ask me now."
        }
    }
}

private struct RevealAnkyThinkingPrompt: View {
    let status: String

    private let messages = [
        "i am reading slowly. not looking for a summary.",
        "i am listening for the pressure under the words.",
        "i am keeping the thread intact while the mirror answers.",
        "still here. some reflections take a little longer.",
        "i am bringing it back without flattening it.",
        "stay close. the page is not gone."
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let index = Int(timeline.date.timeIntervalSinceReferenceDate / 3.4) % messages.count
            let firstLine = status.isEmpty ? "i am staying with this .anky." : status
            ZStack(alignment: .top) {
                AnkyCompanionPromptView(
                    state: .mirrorLoading,
                    message: "\(firstLine)\n\n\(messages[index])"
                )

                ReflectionSeekingSpinner(time: timeline.date.timeIntervalSinceReferenceDate)
                    .frame(width: 58, height: 58)
                    .offset(x: sin(timeline.date.timeIntervalSinceReferenceDate * 1.05) * 24, y: -28)
                    .allowsHitTesting(false)
            }
            .padding(.top, 24)
        }
        .onAppear {
            RevealHaptics.subtle()
        }
    }
}

private struct ReflectionSeekingSpinner: View {
    let time: TimeInterval

    var body: some View {
        ZStack {
            Circle()
                .stroke(RevealPalette.gold.opacity(0.08), lineWidth: 8)

            Circle()
                .trim(from: 0.08, to: 0.36)
                .stroke(
                    RevealPalette.goldSoft.opacity(0.36),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(time * 150))

            Circle()
                .trim(from: 0.58, to: 0.72)
                .stroke(
                    RevealPalette.paper.opacity(0.18),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-time * 95))
        }
        .blur(radius: 0.25)
        .opacity(0.72)
        .scaleEffect(0.94 + sin(time * 2.0) * 0.035)
        .accessibilityHidden(true)
    }
}

private struct RevealReflectionDock: View {
    @ObservedObject var viewModel: RevealViewModel
    let openPrivacy: () -> Void
    let tryAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(RevealPalette.gold.opacity(0.86))

                    if viewModel.isAskingAnky {
                        MirrorProgressLine()
                    } else {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .lineSpacing(3)
                            .foregroundStyle(subtitleColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage.lowercased())
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineSpacing(3)
                            .foregroundStyle(Color.red.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !viewModel.isComplete {
                        tryAgainButton
                    } else if viewModel.reflection == nil {
                        reflectionRequestControls
                    }
                }

                if let reflection = viewModel.reflection {
                    NavigationLink {
                        ReflectionScrollPage(reflection: reflection)
                    } label: {
                        ReflectionScrollGlyph()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open reflection")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReflectionDockBackground())
    }

    private var reflectionRequestControls: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.askAnky()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isAskingAnky {
                        ProgressView()
                            .tint(RevealPalette.ink)
                    }
                    Text(viewModel.isAskingAnky ? "getting reflection" : "get reflection")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(RevealPalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RevealPalette.gold, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.48), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmitReflectionRequest)
            .opacity(viewModel.canSubmitReflectionRequest ? 1 : 0.48)

            Button(action: openPrivacy) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RevealPalette.goldSoft)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(RevealPalette.gold.opacity(0.30), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reflection privacy information")

            if viewModel.shouldShowCreditsLink {
                NavigationLink {
                    CreditsPage(viewModel: YouViewModel())
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(RevealPalette.goldSoft)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(RevealPalette.gold.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open credits")
            }
        }
    }

    private var tryAgainButton: some View {
        Button(action: tryAgain) {
            Text("try again")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(RevealPalette.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(RevealPalette.gold, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.48), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if !viewModel.isComplete {
            return "you have to write \(AnkyDuration.completeRitualMinutes) minutes"
        }
        if viewModel.isAskingAnky {
            return "processing"
        }
        if viewModel.reflection != nil {
            return "reflection returned"
        }
        return "get a reflection"
    }

    private var subtitle: String {
        if viewModel.reflection != nil {
            return "tap the scroll to read what came back."
        }
        if !viewModel.isComplete {
            return viewModel.shortSessionMessage
        }
        return creditLine
    }

    private var subtitleColor: Color {
        switch viewModel.creditPromptState {
        case .unavailable:
            return Color.red.opacity(0.82)
        default:
            return RevealPalette.paper.opacity(0.82)
        }
    }

    private var creditLine: String {
        if viewModel.creditsLoading {
            return "checking reflection access..."
        }
        switch viewModel.creditPromptState {
        case .available, .freeGift:
            return "ready to mirror this artifact."
        case .unavailable:
            return "reflection access is empty."
        case .unknown:
            return "ready to mirror when the signal is open."
        }
    }

}

private struct MirrorProgressLine: View {
    private let messages = [
        "carrying your writing to the mirror...",
        "listening for the shape underneath...",
        "bringing the reflection back..."
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let index = Int(timeline.date.timeIntervalSinceReferenceDate / 2.1) % messages.count
            Text(messages[index])
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(RevealPalette.paper.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }
}

private struct ReflectionScrollGlyph: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 3.0) + 1) / 2
            ZStack {
                Circle()
                    .fill(RevealPalette.gold.opacity(0.22 + pulse * 0.18))
                    .frame(width: 42, height: 42)
                    .blur(radius: 5)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RevealPalette.copiedPaper, RevealPalette.gold, RevealPalette.copiedPaper],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.64), lineWidth: 1)
                    )
                    .rotationEffect(.degrees(-8 + pulse * 3))

                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RevealPalette.ink.opacity(0.78))
                    .offset(x: 1, y: -1)
            }
            .frame(width: 48, height: 48)
        }
    }
}

private struct ReflectionDockBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: 0.035, green: 0.049, blue: 0.082).opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.64), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(RevealPalette.gold.opacity(0.30), lineWidth: 1)
                    .padding(3)
            )
            .shadow(color: Color.black.opacity(0.44), radius: 20, y: 10)
    }
}

private struct ReflectionPrivacySheet: View {
    var body: some View {
        ZStack {
            RevealPalette.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("reflection privacy")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(RevealPalette.gold)

                Text("your writing stays on this device unless you tap get reflection. then anky sends this .anky to the mirror service, verifies the hash, reconstructs the writing for processing, and returns a markdown reflection. anky does not need to store a writing archive for this interaction.")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .lineSpacing(6)
                    .foregroundStyle(RevealPalette.paper.opacity(0.86))

                Text("use it only when you want this piece of writing to leave the device for processing.")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineSpacing(5)
                    .foregroundStyle(RevealPalette.paper.opacity(0.62))

                Spacer()
            }
            .padding(24)
        }
    }
}

private struct ReflectionScrollPage: View {
    let reflection: LocalReflection

    var body: some View {
        ZStack {
            RevealPalette.ink.ignoresSafeArea()
            RevealBackgroundTexture()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        ReflectionScrollGlyph()
                            .frame(width: 54, height: 54)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)

                    SelectableReflectionText(text: reflection.displayBody, isHighlighted: false, style: .readingPage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 56)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RevealPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct SelectableWritingText: UIViewRepresentable {
    let text: String
    let isHighlighted: Bool
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = UIColor(RevealPalette.gold)
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        textView.backgroundColor = .clear
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont(name: "Georgia", size: 19) ?? UIFont.systemFont(ofSize: 19),
                .foregroundColor: UIColor(RevealPalette.paper),
                .paragraphStyle: paragraph,
                .shadow: copyShadow(isHighlighted)
            ]
        )
        textView.layer.cornerRadius = 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    private func copyShadow(_ isHighlighted: Bool) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(isHighlighted ? RevealPalette.copyMagenta : Color.clear)
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 0
        return shadow
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }
            onTap(recognizer.location(in: nil))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct RevealActions: View {
    @ObservedObject var viewModel: RevealViewModel

    var body: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(RevealPalette.gold.opacity(0.13))
                .frame(height: 1)

            if !viewModel.reflectionActionStatus.isEmpty {
                Text(viewModel.reflectionActionStatus)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RevealPalette.paper.opacity(0.52))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }

            if viewModel.canAskAnky {
                Text(viewModel.creditPromptMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(creditTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                ThreadedActionButton(
                    title: viewModel.isAskingAnky ? "anky is listening" : "mirror this",
                    badge: nil,
                    isLoading: viewModel.isAskingAnky,
                    action: {
                        Task {
                            await viewModel.askAnky()
                        }
                    }
                )
                .disabled(!viewModel.canSubmitReflectionRequest)
                .opacity(viewModel.canSubmitReflectionRequest ? 1 : 0.52)

                if viewModel.shouldShowCreditsLink {
                    NavigationLink {
                        CreditsPage(viewModel: YouViewModel())
                    } label: {
                        Text("open credits")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(RevealPalette.goldSoft)
                            .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var creditTextColor: Color {
        switch viewModel.creditPromptState {
        case .unavailable:
            return Color.red.opacity(0.82)
        default:
            return RevealPalette.goldSoft.opacity(0.82)
        }
    }
}

private struct ThreadedActionButton: View {
    let title: String
    let badge: String?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                ThreadOverlay()

                HStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .tint(RevealPalette.paper)
                    }

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))

                    Spacer(minLength: 8)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RevealPalette.goldSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.2), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(RevealPalette.gold.opacity(0.22), lineWidth: 1)
                            )
                    }
                }
                .foregroundStyle(RevealPalette.paper)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(minHeight: 70)
            }
            .background(RevealPalette.buttonFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(RevealPalette.gold.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ThreadOverlay: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.clear,
                    RevealPalette.violet.opacity(0.1),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack {
                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.22))
                    .frame(height: 1)
                    .padding(.top, 10)
                Spacer()
                Rectangle()
                    .fill(RevealPalette.gold.opacity(0.16))
                    .frame(height: 1)
                    .padding(.bottom, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SavedReflectionPanel: View {
    let reflection: LocalReflection
    let isHighlighted: Bool
    let onTap: (CGPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reflection.title.lowercased())
                .font(.custom("Georgia", size: 23).weight(.bold))
                .foregroundStyle(RevealPalette.markdownHeading)
                .tracking(0)
                .textSelection(.enabled)
                .shadow(color: isHighlighted ? RevealPalette.copyMagenta : .clear, radius: 0, x: 2, y: 2)
                .onTapGesture(coordinateSpace: .named("revealRoot")) { location in
                    onTap(location)
                }

            SelectableReflectionText(text: reflection.displayBody, isHighlighted: isHighlighted, onTap: onTap)

        }
    }
}

private extension LocalReflection {
    var displayBody: String {
        reflection.removingLeadingMarkdownHeading(matching: title)
    }
}

private extension String {
    func removingLeadingMarkdownHeading(matching title: String) -> String {
        let lines = replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let headingIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let heading = Self.markdownHeadingText(from: lines[headingIndex]),
              Self.normalizedHeading(heading) == Self.normalizedHeading(title) else {
            return self
        }

        var bodyStart = headingIndex + 1
        while bodyStart < lines.count, lines[bodyStart].trimmingCharacters(in: .whitespaces).isEmpty {
            bodyStart += 1
        }

        return lines.dropFirst(bodyStart).joined(separator: "\n")
    }

    private static func markdownHeadingText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["### ", "## ", "# "] {
            if trimmed.hasPrefix(marker) {
                return String(trimmed.dropFirst(marker.count))
            }
        }
        return nil
    }

    private static func normalizedHeading(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private enum ReflectionTextStyle {
    case standard
    case readingPage

    var bodyFontSize: CGFloat {
        switch self {
        case .standard: 16
        case .readingPage: 18
        }
    }

    var headingFontSize: CGFloat {
        switch self {
        case .standard: 20
        case .readingPage: 25
        }
    }

    var codeFontSize: CGFloat {
        switch self {
        case .standard: 15
        case .readingPage: 16
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .standard: 5
        case .readingPage: 7
        }
    }

    var paragraphSpacing: CGFloat {
        switch self {
        case .standard: 4
        case .readingPage: 8
        }
    }
}

private struct SelectableReflectionText: UIViewRepresentable {
    let text: String
    let isHighlighted: Bool
    let onTap: ((CGPoint) -> Void)?
    var style: ReflectionTextStyle = .standard

    init(
        text: String,
        isHighlighted: Bool,
        onTap: ((CGPoint) -> Void)? = nil,
        style: ReflectionTextStyle = .standard
    ) {
        self.text = text
        self.isHighlighted = isHighlighted
        self.onTap = onTap
        self.style = style
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = UIColor(RevealPalette.gold)
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onTap = onTap
        textView.backgroundColor = .clear
        textView.attributedText = attributedReflection()
        textView.layer.cornerRadius = 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func attributedReflection() -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            result.append(attributedLine(line))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    private func attributedLine(_ line: String) -> NSAttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = trimmed.isEmpty ? style.paragraphSpacing + 5 : style.paragraphSpacing

        if trimmed.isEmpty {
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

        if let heading = headingText(from: trimmed) {
            return NSAttributedString(
                string: heading,
                attributes: [
                    .font: UIFont(name: "Georgia-Bold", size: style.headingFontSize) ?? UIFont.boldSystemFont(ofSize: style.headingFontSize),
                    .foregroundColor: UIColor(RevealPalette.markdownHeading),
                    .paragraphStyle: paragraph,
                    .shadow: copyShadow
                ]
            )
        }

        if let quote = quoteText(from: trimmed) {
            let attributed = NSMutableAttributedString(string: quote, attributes: baseAttributes(paragraph: paragraph, italic: true))
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor(RevealPalette.paper.opacity(0.68)),
                range: NSRange(location: 0, length: attributed.length)
            )
            return attributed
        }

        if let bullet = bulletText(from: trimmed) {
            return inlineAttributedString("• \(bullet)", paragraph: paragraph)
        }

        if let numbered = numberedText(from: trimmed) {
            return inlineAttributedString("\(numbered.marker) \(numbered.text)", paragraph: paragraph)
        }

        return inlineAttributedString(trimmed, paragraph: paragraph)
    }

    private func headingText(from line: String) -> String? {
        for marker in ["### ", "## ", "# "] {
            if line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
        }
        return nil
    }

    private func bulletText(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private func quoteText(from line: String) -> String? {
        guard line.hasPrefix(">") else {
            return nil
        }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private func numberedText(from line: String) -> (marker: String, text: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }
        let numberText = line[..<dotIndex]
        let restStart = line.index(after: dotIndex)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              restStart < line.endIndex,
              line[restStart] == " " else {
            return nil
        }
        return ("\(numberText).", String(line[line.index(after: restStart)...]))
    }

    private func inlineAttributedString(_ text: String, paragraph: NSMutableParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex

        while index < text.endIndex {
            if text[index...].hasPrefix("**"),
               let end = text[text.index(index, offsetBy: 2)...].range(of: "**") {
                let contentStart = text.index(index, offsetBy: 2)
                append(String(text[contentStart..<end.lowerBound]), to: result, inlineStyle: .strong, paragraph: paragraph)
                index = end.upperBound
            } else if text[index] == "*",
                      let end = text[text.index(after: index)...].firstIndex(of: "*") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: result, inlineStyle: .emphasis, paragraph: paragraph)
                index = text.index(after: end)
            } else if text[index] == "`",
                      let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: result, inlineStyle: .code, paragraph: paragraph)
                index = text.index(after: end)
            } else if text[index] == "*" || text[index] == "`" {
                append(String(text[index]), to: result, inlineStyle: .normal, paragraph: paragraph)
                index = text.index(after: index)
            } else {
                let nextStrong = text[index...].range(of: "**")?.lowerBound
                let nextEmphasis = text[index...].firstIndex(of: "*")
                let nextCode = text[index...].firstIndex(of: "`")
                let next = [nextStrong, nextEmphasis, nextCode].compactMap { $0 }.min() ?? text.endIndex
                append(String(text[index..<next]), to: result, inlineStyle: .normal, paragraph: paragraph)
                index = next
            }
        }

        return result
    }

    private func baseAttributes(paragraph: NSMutableParagraphStyle, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        [
            .font: italic
                ? UIFont.italicSystemFont(ofSize: style.bodyFontSize)
                : (UIFont(name: "Georgia", size: style.bodyFontSize) ?? UIFont.systemFont(ofSize: style.bodyFontSize)),
            .foregroundColor: UIColor(RevealPalette.paper),
            .paragraphStyle: paragraph,
            .shadow: copyShadow
        ]
    }

    private var copyShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(isHighlighted ? RevealPalette.copyMagenta : Color.clear)
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 0
        return shadow
    }

    private func append(
        _ string: String,
        to result: NSMutableAttributedString,
        inlineStyle: InlineStyle,
        paragraph: NSMutableParagraphStyle
    ) {
        var attributes = baseAttributes(paragraph: paragraph)
        switch inlineStyle {
        case .normal:
            break
        case .strong:
            attributes[.foregroundColor] = UIColor(RevealPalette.gold)
            attributes[.font] = UIFont(name: "Georgia-Bold", size: style.bodyFontSize) ?? UIFont.boldSystemFont(ofSize: style.bodyFontSize)
        case .emphasis:
            attributes[.font] = UIFont(name: "Georgia-Italic", size: style.bodyFontSize) ?? UIFont.italicSystemFont(ofSize: style.bodyFontSize)
        case .code:
            attributes[.foregroundColor] = UIColor(RevealPalette.paper.opacity(0.82))
            attributes[.font] = UIFont.monospacedSystemFont(ofSize: style.codeFontSize, weight: .regular)
        }
        result.append(NSAttributedString(string: string, attributes: attributes))
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: ((CGPoint) -> Void)?

        init(onTap: ((CGPoint) -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }
            onTap?(recognizer.location(in: nil))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    private enum InlineStyle {
        case normal
        case strong
        case emphasis
        case code
    }
}

private enum RevealPalette {
    static let appBackground = Color(hex: 0x08090B)
    static let ink = Color(hex: 0x080713)
    static let paper = Color(hex: 0xFFF0C9)
    static let gold = Color(hex: 0xE8C879)
    static let markdownHeading = Color(hex: 0xF6D978)
    static let violet = Color(hex: 0x6F5DFF)
    static let goldSoft = gold.opacity(0.72)
    static let copiedPaper = Color(hex: 0xFFF8DC)
    static let copiedGlow = Color(hex: 0xF8D97A)
    static let copyFlashText = Color(hex: 0xFFFFFF)
    static let copyMagenta = Color(hex: 0xFF3BD4)
    static let copyButtonFill = Color(hex: 0x120F0B)
    static let buttonFill = Color(red: 68 / 255, green: 48 / 255, blue: 23 / 255).opacity(0.62)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
