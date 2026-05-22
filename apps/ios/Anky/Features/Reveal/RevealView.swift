import SwiftUI
import UIKit

struct RevealView: View {
    @StateObject private var viewModel: RevealViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var copiedSection: RevealCopySection?
    @State private var showReflectionScroll = false
    @State private var showPrivacyInfo = false
    private let onDeleted: () -> Void

    init(viewModel: RevealViewModel, onDeleted: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDeleted = onDeleted
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

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        SelectableWritingText(
                            text: viewModel.reconstructedText,
                            isHighlighted: copiedSection == .writing
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .id(RevealScrollTarget.writing)

                        PrivacyDivider()
                            .padding(.top, 34)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 238)
                }
                .overlay(alignment: .topTrailing) {
                    FloatingCopyButton(section: .writing, isCopied: copiedSection == .writing) {
                        copyActiveSection()
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 20)
                }
            }

            VStack {
                Spacer()
                RevealReflectionDock(
                    viewModel: viewModel,
                    openPrivacy: { showPrivacyInfo = true },
                    openReflection: { showReflectionScroll = true }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .ignoresSafeArea(.keyboard)
            .zIndex(30)
        }
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
        .sheet(isPresented: $showPrivacyInfo) {
            ReflectionPrivacySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReflectionScroll) {
            if let reflection = viewModel.reflection {
                ReflectionScrollSheet(reflection: reflection)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            Task {
                await viewModel.refreshCredits(showError: false)
            }
        }
        .onChange(of: viewModel.isDeleted) { _, isDeleted in
            guard isDeleted else {
                return
            }
            onDeleted()
            dismiss()
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

    private var activeCopySection: RevealCopySection {
        .writing
    }

    private func copyActiveSection() {
        let section = activeCopySection
        RevealHaptics.selection()
        viewModel.copy(section)
        withAnimation(.easeOut(duration: 0.08)) {
            copiedSection = section
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            guard copiedSection == section else {
                return
            }
            withAnimation(.easeOut(duration: 0.22)) {
                copiedSection = nil
            }
        }
    }

}

private enum RevealHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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

private struct RevealReflectionDock: View {
    @ObservedObject var viewModel: RevealViewModel
    let openPrivacy: () -> Void
    let openReflection: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AnkyWitnessView(mood: .warm, size: .companion, sequence: sequence)
                    .frame(width: 78, height: 78)

                if viewModel.reflection != nil {
                    Button(action: openReflection) {
                        ReflectionScrollGlyph()
                    }
                    .buttonStyle(.plain)
                    .offset(x: 12, y: -6)
                    .accessibilityLabel("Open reflection")
                }
            }
            .frame(width: 92, height: 84)

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

                if viewModel.reflection == nil {
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReflectionDockBackground())
        }
    }

    private var title: String {
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
            return "complete 8 minutes to unlock reflection."
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
            return "checking credits..."
        }
        switch viewModel.creditPromptState {
        case .available(let count):
            return "\(count) \(count == 1 ? "credit" : "credits") left."
        case .freeGift(let count):
            return "\(count) free \(count == 1 ? "credit" : "credits") left."
        case .unavailable:
            return "no credits left."
        case .unknown:
            return "credits update after reflection."
        }
    }

    private var sequence: AnkySequenceName {
        if viewModel.isAskingAnky {
            return .shyListening
        }
        if viewModel.reflection != nil {
            return .celebrate
        }
        return .idleBlink
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

private struct ReflectionScrollSheet: View {
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text(reflection.title.lowercased())
                                .font(.custom("Georgia", size: 24).weight(.bold))
                                .foregroundStyle(RevealPalette.markdownHeading)

                            if let creditsRemaining = reflection.creditsRemaining {
                                Text("\(creditsRemaining) \(creditsRemaining == 1 ? "credit" : "credits") left")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(RevealPalette.goldSoft)
                            }
                        }
                    }

                    SelectableReflectionText(text: reflection.reflection, isHighlighted: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(RevealPalette.paper.opacity(0.075))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(RevealPalette.gold.opacity(0.24), lineWidth: 1)
                        )
                )
                .padding(18)
            }
        }
    }
}

private struct SelectableWritingText: UIViewRepresentable {
    let text: String
    let isHighlighted: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
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

    private func copyShadow(_ isHighlighted: Bool) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(isHighlighted ? RevealPalette.copyMagenta : Color.clear)
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 0
        return shadow
    }
}

private struct RevealActions: View {
    @ObservedObject var viewModel: RevealViewModel

    var body: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(RevealPalette.gold.opacity(0.13))
                .frame(height: 1)

            if viewModel.isAskingAnky {
                MirrorWitnessLoadingView()
                    .padding(.top, 4)
            }

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

private struct MirrorWitnessLoadingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                AnkyWitnessView(mood: .warm, size: .small, sequence: .idleBlink)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(RevealPalette.goldSoft.opacity(0.82), lineWidth: 1.4)
                    .background(RevealPalette.paper.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .frame(width: 18, height: 24)
                    .rotationEffect(.degrees(-8))
                    .offset(x: 22, y: 6)
            }
            .frame(width: 70, height: 54)

            Text("Anky is listening...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(RevealPalette.paper.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
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

private struct FloatingCopyButton: View {
    let section: RevealCopySection
    let isCopied: Bool
    let action: () -> Void

    private var label: String {
        switch section {
        case .writing:
            return isCopied ? "copied writing" : "copy writing"
        case .reflection:
            return isCopied ? "copied reflection" : "copy reflection"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isCopied ? RevealPalette.copyMagenta : RevealPalette.paper)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RevealPalette.copyButtonFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke((isCopied ? RevealPalette.copyMagenta : RevealPalette.gold).opacity(isCopied ? 0.72 : 0.32), lineWidth: 1)
            )
            .shadow(color: isCopied ? RevealPalette.copyMagenta.opacity(0.32) : Color.black.opacity(0.38), radius: isCopied ? 12 : 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct SavedReflectionPanel: View {
    let reflection: LocalReflection
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(reflection.title.lowercased())
                .font(.custom("Georgia", size: 23).weight(.bold))
                .foregroundStyle(RevealPalette.markdownHeading)
                .tracking(0)
                .shadow(color: isHighlighted ? RevealPalette.copyMagenta : .clear, radius: 0, x: 2, y: 2)

            SelectableReflectionText(text: reflection.reflection, isHighlighted: isHighlighted)

            if let creditsRemaining = reflection.creditsRemaining {
                Text("\(creditsRemaining) \(creditsRemaining == 1 ? "reflection" : "reflections") left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RevealPalette.goldSoft.opacity(0.78))
            }
        }
    }
}

private struct SelectableReflectionText: UIViewRepresentable {
    let text: String
    let isHighlighted: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.backgroundColor = .clear
        textView.attributedText = attributedReflection()
        textView.layer.cornerRadius = 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 56
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
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
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = trimmed.isEmpty ? 9 : 4

        if trimmed.isEmpty {
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

        if let heading = headingText(from: trimmed) {
            return NSAttributedString(
                string: heading,
                attributes: [
                    .font: UIFont(name: "Georgia-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20),
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
                append(String(text[contentStart..<end.lowerBound]), to: result, style: .strong, paragraph: paragraph)
                index = end.upperBound
            } else if text[index] == "`",
                      let end = text[text.index(after: index)...].firstIndex(of: "`") {
                let contentStart = text.index(after: index)
                append(String(text[contentStart..<end]), to: result, style: .code, paragraph: paragraph)
                index = text.index(after: end)
            } else {
                let nextStrong = text[index...].range(of: "**")?.lowerBound
                let nextCode = text[index...].firstIndex(of: "`")
                let next = [nextStrong, nextCode].compactMap { $0 }.min() ?? text.endIndex
                append(String(text[index..<next]), to: result, style: .normal, paragraph: paragraph)
                index = next
            }
        }

        return result
    }

    private func baseAttributes(paragraph: NSMutableParagraphStyle, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        [
            .font: italic
                ? UIFont.italicSystemFont(ofSize: 16)
                : (UIFont(name: "Georgia", size: 16) ?? UIFont.systemFont(ofSize: 16)),
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
        style: InlineStyle,
        paragraph: NSMutableParagraphStyle
    ) {
        var attributes = baseAttributes(paragraph: paragraph)
        switch style {
        case .normal:
            break
        case .strong:
            attributes[.foregroundColor] = UIColor(RevealPalette.gold)
            attributes[.font] = UIFont(name: "Georgia-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        case .code:
            attributes[.foregroundColor] = UIColor(RevealPalette.paper.opacity(0.82))
            attributes[.font] = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        }
        result.append(NSAttributedString(string: string, attributes: attributes))
    }

    private enum InlineStyle {
        case normal
        case strong
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
