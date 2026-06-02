import SwiftUI
import UIKit

struct RevealView: View {
    @StateObject private var viewModel: RevealViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ankyCompanion: AnkyCompanionStore
    @State private var confirmDelete = false
    @State private var copiedSection: RevealCopySection?
    @State private var copyBurst: RevealCopyBurst?
    @State private var didAutoStartReflection = false
    @State private var reflectionScrollRequest = 0
    @State private var inlineReflectionActive = false
    @State private var didScrollToStreamingStart = false
    @State private var isReflectionVisible = false
    private let onDeleted: () -> Void
    private let onTryAgain: () -> Void
    private let startsReflectionOnAppear: Bool

    init(
        viewModel: RevealViewModel,
        startsReflectionOnAppear: Bool = false,
        onDeleted: @escaping () -> Void = {},
        onTryAgain: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.startsReflectionOnAppear = startsReflectionOnAppear
        self.onDeleted = onDeleted
        self.onTryAgain = onTryAgain
    }

    var body: some View {
        ZStack {
            RevealPalette.ink
                .ignoresSafeArea()

            RevealBackgroundTexture()

            VStack(spacing: 0) {
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
                                .trackReflectionVisibility()
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if !viewModel.streamingReflectionMarkdown.isEmpty {
                                StreamingReflectionPanel(
                                    markdown: viewModel.streamingReflectionMarkdown
                                )
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            } else if inlineReflectionActive, let errorMessage = viewModel.errorMessage {
                                ReflectionErrorPanel(
                                    message: errorMessage
                                )
                                .padding(.top, 36)
                                .id(RevealScrollTarget.reflection)
                                .trackReflectionVisibility()
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, shouldShowBottomAction ? 138 : 72)
                    }
                    .onChange(of: reflectionScrollRequest) { _, _ in
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onChange(of: viewModel.reflection?.id) { _, reflectionID in
                        guard reflectionID != nil else { return }
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onChange(of: viewModel.streamingReflectionMarkdown) { oldValue, newValue in
                        guard oldValue.isEmpty, !newValue.isEmpty, !didScrollToStreamingStart else { return }
                        didScrollToStreamingStart = true
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onChange(of: viewModel.errorMessage) { _, errorMessage in
                        guard inlineReflectionActive, errorMessage != nil else { return }
                        scrollToReflection(with: scrollProxy, anchor: .top)
                    }
                    .onPreferenceChange(ReflectionVisibilityPreferenceKey.self) { isVisible in
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            isReflectionVisible = isVisible
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

            if shouldShowBottomAction {
                RevealBottomActionButton(
                    title: bottomActionTitle,
                    isLoading: viewModel.isAskingAnky,
                    isEnabled: bottomActionIsEnabled,
                    action: bottomAction
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(60)
            }
        }
        .coordinateSpace(name: "revealRoot")
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(viewModel.compactHeaderLine.lowercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RevealPalette.ink.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    RevealHaptics.warning()
                    confirmDelete = true
                } label: {
                    if viewModel.isDeleting {
                        ProgressView()
                            .tint(RevealPalette.paper)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.88))
                    }
                }
                .disabled(viewModel.isDeleting)
                .accessibilityLabel("Delete writing session")
            }
        }
        .confirmationDialog("Delete forever?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RevealHaptics.warning()
                viewModel.deleteSession()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this writing session. This cannot be undone.")
        }
        .onAppear {
            Task {
                await viewModel.refreshCredits(showError: false)
            }
            ankyCompanion.hideBubble()
            if startsReflectionOnAppear, !didAutoStartReflection, viewModel.reflection == nil {
                didAutoStartReflection = true
                beginInlineReflection()
            }
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
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: shouldShowBottomAction)
    }

    private func beginInlineReflection() {
        inlineReflectionActive = true
        didScrollToStreamingStart = false
        requestReflectionScroll()
        ankyCompanion.hideBubble(returningTo: .thinking)
        Task {
            await viewModel.askAnky()
            requestReflectionScroll()
        }
    }

    private func requestReflectionScroll() {
        withAnimation(.easeInOut(duration: 0.45)) {
            reflectionScrollRequest += 1
        }
    }

    private func scrollToReflection(with proxy: ScrollViewProxy, anchor: UnitPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.58)) {
                proxy.scrollTo(RevealScrollTarget.reflection, anchor: anchor)
            }
        }
    }

    private var shouldShowBottomAction: Bool {
        if viewModel.reflection != nil {
            return !isReflectionVisible
        }
        return true
    }

    private var bottomActionTitle: String {
        if viewModel.isAskingAnky {
            return "LOADING"
        }
        if viewModel.reflection != nil {
            return "READ REFLECTION"
        }
        if viewModel.isComplete {
            return "REFLECT THIS ANKY"
        }
        return "WRITE \(AnkyDuration.completeRitualMinutes) MINUTES"
    }

    private var bottomActionIsEnabled: Bool {
        if viewModel.isAskingAnky {
            return false
        }
        if viewModel.reflection != nil {
            return true
        }
        return viewModel.isComplete ? viewModel.canSubmitReflectionRequest : true
    }

    private func bottomAction() {
        if viewModel.reflection != nil {
            requestReflectionScroll()
        } else if viewModel.isComplete {
            beginInlineReflection()
        } else {
            onTryAgain()
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

private struct RevealBottomActionButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                        .tint(RevealPalette.ink)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .tracking(0.35)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)
            }
            .foregroundStyle(RevealPalette.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(RevealPalette.gold, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.48), lineWidth: 1)
            )
            .shadow(color: RevealPalette.gold.opacity(0.28), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isLoading ? 1 : 0.48)
        .accessibilityLabel(title)
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
    let metadata: String
    let isDeleting: Bool
    let dismiss: DismissAction
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RevealHeaderGlassButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back",
                tint: RevealPalette.paper,
                stroke: RevealPalette.gold.opacity(0.24),
                action: {
                    dismiss()
                }
            )

            Text(metadata.lowercased())
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(RevealPalette.paper.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            RevealHeaderGlassButton(
                systemName: "trash",
                accessibilityLabel: "Delete writing session",
                tint: Color.red.opacity(0.88),
                stroke: Color.red.opacity(0.22),
                isLoading: isDeleting,
                isEnabled: !isDeleting,
                action: delete
            )
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

private struct RevealHeaderGlassButton: View {
    let systemName: String
    let accessibilityLabel: String
    let tint: Color
    let stroke: Color
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    private let size: CGFloat = 40

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(tint)
            .frame(width: 50, height: 50)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Button(action: action) {
                label
                    .background(Color.black.opacity(0.24), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var label: some View {
        if #available(iOS 26.0, *) {
            if isLoading {
                ProgressView()
                    .tint(RevealPalette.paper)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: systemName == "trash" ? 17 : 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
        } else {
            if isLoading {
                ProgressView()
                    .tint(RevealPalette.paper)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: systemName == "trash" ? 15 : 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
        }
    }
}

private enum RevealScrollTarget {
    case writing
    case reflection
}

private struct ReflectionVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private extension View {
    func trackReflectionVisibility() -> some View {
        background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                let screenHeight = UIScreen.main.bounds.height
                let isVisible = frame.minY < screenHeight - 138 && frame.maxY > 128

                Color.clear.preference(key: ReflectionVisibilityPreferenceKey.self, value: isVisible)
            }
        )
    }
}

struct RevealBackgroundTexture: View {
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
    var body: some View {
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
        .accessibilityHidden(true)
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

private struct StreamingReflectionPanel: View {
    let markdown: String

    var body: some View {
        SelectableReflectionText(
            text: markdown,
            isHighlighted: false
        )
        .opacity(0.92)
    }
}

private struct ReflectionErrorPanel: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("the mirror did not open")
                .font(.custom("Georgia", size: 28).weight(.bold))
                .foregroundStyle(RevealPalette.markdownHeading)
                .tracking(0)

            Text(message.lowercased())
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.red.opacity(0.82))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
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

        if isHorizontalRule(trimmed) {
            paragraph.lineSpacing = 0
            paragraph.paragraphSpacingBefore = 12
            paragraph.paragraphSpacing = 12
            return NSAttributedString(string: "", attributes: [.paragraphStyle: paragraph])
        }

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

    private func isHorizontalRule(_ line: String) -> Bool {
        if line == "---" || line == "***" || line == "___" || line == "\u{2014}" {
            return true
        }
        guard line.count <= 5 else {
            return false
        }
        return !line.isEmpty && line.allSatisfy { character in
            character == "-" || character == "*" || character == "_" || character == "\u{2014}"
        }
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

enum RevealPalette {
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
