import SwiftUI
import UIKit

struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyboardFrame: CGRect?
    @State private var lastObservedKeyboardHeight: CGFloat?
    @State private var writingPreferences = WritingPreferencesStore().load()
    @State private var dailyTargetMs = DailyTargetStore().effectiveTargetMs()
    let shouldFocus: Bool
    private let onCompleted: (SavedAnky) -> Void
    private let onCloseToMap: () -> Void

    init(
        viewModel: WriteViewModel,
        shouldFocus: Bool,
        onCompleted: @escaping (SavedAnky) -> Void,
        onCloseToMap: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.shouldFocus = shouldFocus
        self.onCompleted = onCompleted
        self.onCloseToMap = onCloseToMap
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let globalFrame = geometry.frame(in: .global)
                let shouldPreReserveKeyboard = shouldFocus && viewModel.canAcceptInput && keyboardFrame == nil
                let keyboardTop = keyboardFrame?.minY ?? (
                    shouldPreReserveKeyboard
                    ? globalFrame.maxY - reservedKeyboardHeight(
                        containerSize: geometry.size,
                        safeAreaBottom: geometry.safeAreaInsets.bottom
                    )
                    : globalFrame.maxY
                )
                let keyboardOverlap = max(0, globalFrame.maxY - keyboardTop)
                let keyboardIsVisible = keyboardTop < globalFrame.maxY
                let textViewHeight = max(1, geometry.size.height)
                let textBottomInset: CGFloat = keyboardOverlap + (keyboardIsVisible ? 24 : 36)
                let textSideInset: CGFloat = 24
                let acceptsWritingInput = shouldFocus && viewModel.canAcceptInput

                ForwardOnlyTextView(
                    glyphs: viewModel.displayedGlyphs,
                    focusID: viewModel.keyboardFocusID,
                    shouldFocus: acceptsWritingInput,
                    bottomInset: textBottomInset,
                    rightInset: textSideInset,
                    textOpacity: writingTextOpacity,
                    colorScheme: colorScheme,
                    preferences: writingPreferences,
                    onText: viewModel.accept,
                    onReplaceTail: viewModel.replaceForwardTail,
                    onRejectedInput: viewModel.nudgeInvalidInput
                )
                .frame(width: geometry.size.width, height: textViewHeight)
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                WritingTopChrome(
                    state: writingPillState,
                    timeText: timerText,
                    timeCaption: timerCaption,
                    silenceProgress: silenceProgress,
                    showsBackButton: !viewModel.hasStarted,
                    onBack: {
                        viewModel.persistForNavigation()
                        onCloseToMap()
                    },
                    onFocus: {
                        viewModel.focusWritingKeyboard()
                    }
                )
                .padding(.horizontal, 14)
                .frame(width: geometry.size.width, height: 156, alignment: .top)
                .position(x: geometry.size.width / 2, y: geometry.safeAreaInsets.top + 84)
                .zIndex(20)

                // §5.4: the passive Quick Pass line — quiet, contextual, no
                // button. Appears only for gate-originated sessions.
                if let unlockLine = viewModel.quickPassUnlockLine {
                    Text(unlockLine)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.ankyPaper.opacity(0.78), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.ankyGold.opacity(0.35), lineWidth: 0.5))
                        .frame(maxWidth: geometry.size.width - 28)
                        .position(x: geometry.size.width / 2, y: geometry.safeAreaInsets.top + 154)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(21)
                        .animation(.easeInOut(duration: 0.5), value: unlockLine)
                }
            }
        }
        // Phase-2 §7 sepia pass: the writing surface is parchment — utterly
        // plain, no wash motion, a faint spiral resting in the top corner.
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color.ankyPaper, Color.ankyPaperDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                AnkySunGlyph()
                    .frame(width: 96, height: 96)
                    .opacity(0.07)
                    .padding(.top, 10)
                    .padding(.trailing, -18)
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsMapButton ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {}
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardFrame(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { notification in
            updateKeyboardFrame(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { notification in
            updateKeyboardFrame(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            updateKeyboardFrame(nil)
        }
        .onAppear {
            writingPreferences = WritingPreferencesStore().load()
            dailyTargetMs = DailyTargetStore().effectiveTargetMs()
            viewModel.bindCompletion(onCompleted)
            if shouldFocus {
                viewModel.prepareForWritingScene()
            }
            viewModel.closeIfSilenceElapsed()
        }
        .onChange(of: shouldFocus) { isFocused in
            if isFocused {
                viewModel.prepareForWritingScene()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, shouldFocus {
                viewModel.prepareForWritingScene()
                viewModel.closeIfSilenceElapsed()
            } else {
                viewModel.persistOnBackground()
            }
        }
    }

    private var writingTextOpacity: Double {
        1
    }

    /// Counts down to the writer's daily target, then counts what they
    /// have written past it.
    private var timerText: String {
        let remaining = dailyTargetMs - viewModel.elapsedMs
        if remaining > 0 {
            return AnkyDuration.clock(remaining)
        }
        return AnkyDuration.clock(viewModel.elapsedMs)
    }

    private var timerCaption: String {
        dailyTargetMs - viewModel.elapsedMs > 0 ? "remaining" : "written"
    }

    private var showsMapButton: Bool {
        false
    }

    private var writingPillState: WritingSessionPillState {
        guard viewModel.hasStarted else {
            return .empty
        }
        if viewModel.writeBeforeScrollSessionMetrics.hasDailyUnlockAvailable {
            return .daily
        }
        if viewModel.writeBeforeScrollSessionMetrics.hasQuickPassAvailable {
            return .quick
        }
        if viewModel.writeBeforeScrollQuickPassesRemaining > 0 {
            return .writing
        }
        return .writingDailyOnly
    }

    private var silenceProgress: Double {
        // The spiral doubles as the stillness indicator on Daily sessions.
        // Quick Pass ends in motion — once the passive unlock has applied,
        // the indicator goes inert; the practice's stillness is not asked
        // of a one-sentence pass.
        if viewModel.hasAppliedPassiveQuickUnlock,
           viewModel.elapsedMs < DailyTargetStore().effectiveTargetMs() {
            return 0
        }
        return min(1, max(0, Double(viewModel.silenceElapsedMs) / Double(AnkyDuration.terminalSilenceMs)))
    }

    private func updateKeyboardFrame(from notification: Notification) {
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        updateKeyboardFrame(frame, from: notification)
    }

    private func updateKeyboardFrame(_ frame: CGRect?, from notification: Notification? = nil) {
        if let frame {
            let height = max(0, UIScreen.main.bounds.maxY - frame.minY)
            if height > 0 {
                lastObservedKeyboardHeight = height
            }
        }

        let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        let animation = Animation.easeOut(duration: max(0.16, duration ?? 0.24))
        withAnimation(animation) {
            keyboardFrame = frame
        }
    }

    private func stableRingCenterY(globalFrame: CGRect, ringRadius: CGFloat) -> CGFloat {
        let targetGlobalY = UIScreen.main.bounds.height * 0.36
        let targetLocalY = targetGlobalY - globalFrame.minY
        let minimumY = ringRadius + 24
        let maximumY = max(minimumY, globalFrame.height - ringRadius - 24)
        return min(max(targetLocalY, minimumY), maximumY)
    }

    private func reservedKeyboardHeight(containerSize: CGSize, safeAreaBottom: CGFloat) -> CGFloat {
        if let lastObservedKeyboardHeight {
            return lastObservedKeyboardHeight
        }
        return predictedKeyboardHeight(containerSize: containerSize, safeAreaBottom: safeAreaBottom)
    }

    private func predictedKeyboardHeight(containerSize: CGSize, safeAreaBottom: CGFloat) -> CGFloat {
        let isPortrait = containerSize.height >= containerSize.width
        let ratio = isPortrait ? 0.40 : 0.36
        let lowerBound: CGFloat = isPortrait ? 300 : 210
        let upperBound: CGFloat = isPortrait ? 380 : 300
        return min(upperBound, max(lowerBound, containerSize.height * ratio)) + safeAreaBottom
    }

}

private enum WritingSessionPillState: Equatable {
    case empty
    case writing
    case writingDailyOnly
    case quick
    case daily

    var title: String {
        switch self {
        case .empty:
            return "write one true thing"
        case .writing:
            return "finish a sentence · opens a 15-min pass"
        case .writingDailyOnly:
            return "write to your target · opens the day"
        case .quick:
            return "stop to unlock · 15 min"
        case .daily:
            return "stop to unlock · rest of day"
        }
    }

    /// The pigment each state washes the pill with.
    var tint: Color {
        switch self {
        case .empty, .writing, .writingDailyOnly:
            return .ankyGold
        case .quick:
            return .ankyApricot
        case .daily:
            return .ankyViolet
        }
    }

    /// The little glyph in the pill's leading medallion.
    var iconName: String {
        switch self {
        case .empty, .writing, .writingDailyOnly:
            return "lock"
        case .quick, .daily:
            return "lock.open"
        }
    }
}

private struct WritingTopChrome: View {
    let state: WritingSessionPillState
    let timeText: String
    let timeCaption: String
    let silenceProgress: Double
    let showsBackButton: Bool
    let onBack: () -> Void
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // The spiral sun holds the center, like in the poster.
                AnkySunGlyph(size: 30, color: .ankyGold)
                    .opacity(chromeOpacity)

                HStack(alignment: .top) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.ankyInkSoft)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(Color.ankyPaper.opacity(0.55))
                                    .overlay(Circle().strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5))
                            }
                    }
                    .buttonStyle(.plain)
                    .opacity(showsBackButton ? chromeOpacity : 0)
                    .allowsHitTesting(showsBackButton)
                    .accessibilityLabel(AnkyLocalization.ui("Back"))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timeText)
                            .font(.system(size: 34, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(Color.ankyInk.opacity(0.88))
                            .contentTransition(.numericText())
                        Text(AnkyLocalization.ui(timeCaption))
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.85))
                    }
                    .opacity(chromeOpacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(AnkyLocalization.ui("Writing time %@", "\(timeText) \(timeCaption)"))
                }
            }

            WritingStatePill(
                state: state,
                isInteractive: state == .empty,
                opacity: chromeOpacity,
                onFocus: onFocus
            )
        }
        .animation(.easeInOut(duration: 0.9), value: showsBackButton)
        .animation(.easeInOut(duration: 0.9), value: state)
        .animation(.linear(duration: 0.16), value: silenceProgress)
    }

    /// The chrome recedes as the eight seconds of silence gather.
    private var chromeOpacity: Double {
        max(0.28, 1 - min(1, max(0, silenceProgress)) * 0.72)
    }
}

private struct WritingStatePill: View {
    let state: WritingSessionPillState
    let isInteractive: Bool
    let opacity: Double
    let onFocus: () -> Void

    var body: some View {
        Group {
            if isInteractive {
                Button(action: onFocus) {
                    pillContent
                }
                .buttonStyle(.plain)
            } else {
                pillContent
            }
        }
        .allowsHitTesting(isInteractive)
        .accessibilityAddTraits(isInteractive ? .isButton : [])
    }

    private var pillContent: some View {
        HStack(spacing: 12) {
            Image(systemName: state.iconName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.ankyInk.opacity(0.75))
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ankyGoldLight.opacity(0.65), Color.ankyPaper.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }

            Text(state.title)
                .id(state)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Color.ankyInk.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)

            AnkySunGlyph(size: 22, color: state.tint)
                .padding(.trailing, 10)
        }
        .padding(6)
        .background {
            Capsule()
                .fill(
                    // A veil of warm paper over the wall, never flat.
                    LinearGradient(
                        colors: [Color.ankyPaper.opacity(0.85), Color.ankyPaperDeep.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(state.tint.opacity(state == .daily ? 0.30 : 0.16), lineWidth: 0.5))
        }
        .shadow(color: Color.ankyViolet.opacity(0.12), radius: 14, y: 5)
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.9), value: state)
    }
}

/// Writing is violet ink; as the eight seconds of sealing silence pass,
/// each glyph warms toward madder — pigment drying into the page.
private enum WritingRhythmColor {
    // Umber on parchment (phase-2 §7 sepia pass) — matches Color.ankyUmber.
    private static let ink = (red: 0.310, green: 0.243, blue: 0.180)
    private static let madder = (red: 0.702, green: 0.325, blue: 0.302)

    static func color(progress: Double, colorScheme: ColorScheme = .dark) -> Color {
        let clamped = min(1, max(0, progress))
        let red = ink.red + (madder.red - ink.red) * clamped
        let green = ink.green + (madder.green - ink.green) * clamped
        let blue = ink.blue + (madder.blue - ink.blue) * clamped
        return Color(.displayP3, red: red, green: green, blue: blue)
    }

    static func uiColor(progress: Double, alpha: Double = 1, colorScheme: ColorScheme = .dark) -> UIColor {
        UIColor(color(progress: progress, colorScheme: colorScheme)).withAlphaComponent(alpha)
    }
}

enum RejectedWritingInput {
    case backspace
    case enter
}


private struct ForwardOnlyTextView: UIViewRepresentable {
    let glyphs: [WritingGlyph]
    let focusID: UUID
    let shouldFocus: Bool
    let bottomInset: CGFloat
    let rightInset: CGFloat
    let textOpacity: Double
    let colorScheme: ColorScheme
    let preferences: WritingPreferences
    let onText: (String) -> Void
    let onReplaceTail: (Int, String) -> Void
    let onRejectedInput: (RejectedWritingInput) -> Void

    private var writingFont: UIFont {
        preferences.fontChoice.uiFont(size: preferences.textSize.pointSize)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = BottomRightAnchoredTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = writingFont
        textView.adjustsFontForContentSizeCategory = false
        textView.textColor = WritingRhythmColor.uiColor(progress: 0, alpha: textOpacity, colorScheme: colorScheme)
        textView.tintColor = UIColor(Color.ankyUmber)
        textView.keyboardAppearance = .light
        textView.textAlignment = .left
        textView.isEditable = shouldFocus
        textView.keyboardDismissMode = .none
        textView.autocorrectionType = preferences.autocorrectEnabled ? .default : .no
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = preferences.autocorrectEnabled ? .default : .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: bottomInset, right: rightInset)
        textView.contentInset = .zero
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = false
        textView.measurementLineSpacing = preferences.textSize.pointSize * 0.42
        textView.updateAnchorInsets(bottom: bottomInset, right: rightInset)

        if shouldFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let renderedText = String(glyphs.map(\.character))
        let font = writingFont
        let shouldRerenderColors = context.coordinator.colorScheme != colorScheme
            || context.coordinator.textOpacity != textOpacity
            || context.coordinator.renderedPreferences != preferences
        if context.coordinator.renderedGlyphs != glyphs || uiView.text != renderedText || shouldRerenderColors {
            uiView.font = font
            uiView.attributedText = makeAttributedText(font: font)
            context.coordinator.renderedGlyphs = glyphs
            context.coordinator.colorScheme = colorScheme
            context.coordinator.textOpacity = textOpacity
            context.coordinator.renderedPreferences = preferences
        }
        context.coordinator.backspaceAllowed = preferences.backspaceAllowed
        uiView.autocorrectionType = preferences.autocorrectEnabled ? .default : .no
        uiView.spellCheckingType = preferences.autocorrectEnabled ? .default : .no
        uiView.textColor = WritingRhythmColor.uiColor(progress: 0, alpha: textOpacity, colorScheme: colorScheme)
        uiView.backgroundColor = .clear
        uiView.isEditable = shouldFocus
        if let anchoredTextView = uiView as? BottomRightAnchoredTextView {
            anchoredTextView.measurementLineSpacing = preferences.textSize.pointSize * 0.42
            anchoredTextView.updateAnchorInsets(bottom: bottomInset, right: rightInset)
        } else {
            uiView.textContainerInset.bottom = bottomInset
            uiView.textContainerInset.right = rightInset
        }
        uiView.verticalScrollIndicatorInsets.bottom = bottomInset
        uiView.contentInset = .zero

        if context.coordinator.focusID != focusID {
            context.coordinator.focusID = focusID
            if shouldFocus {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        }
        if shouldFocus, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !shouldFocus, uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }

        let end = uiView.endOfDocument
        uiView.selectedTextRange = uiView.textRange(from: end, to: end)
        if let anchoredTextView = uiView as? BottomRightAnchoredTextView {
            anchoredTextView.scrollToEndRespectingAnchor()
        } else {
            uiView.scrollRangeToVisible(NSRange(location: (uiView.text as NSString).length, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            focusID: focusID,
            colorScheme: colorScheme,
            textOpacity: textOpacity,
            backspaceAllowed: preferences.backspaceAllowed,
            onText: onText,
            onReplaceTail: onReplaceTail,
            onRejectedInput: onRejectedInput
        )
    }

    private func makeAttributedText(font: UIFont?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = preferences.textSize.pointSize * 0.42

        let textFont = font ?? writingFont
        let attributed = NSMutableAttributedString()
        let latestIndex = glyphs.indices.last

        for index in glyphs.indices {
            let glyph = glyphs[index]
            let isLatest = index == latestIndex
            let alpha = isLatest ? 0.96 : max(0.28, textOpacity * 0.82)
            attributed.append(
                NSAttributedString(
                    string: String(glyph.character),
                    attributes: [
                        .font: textFont,
                        .foregroundColor: WritingRhythmColor.uiColor(progress: glyph.silenceProgress, alpha: alpha, colorScheme: colorScheme),
                        .paragraphStyle: paragraph
                    ]
                )
            )
        }

        return attributed
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var focusID: UUID
        var colorScheme: ColorScheme
        var textOpacity: Double
        var backspaceAllowed: Bool
        var renderedGlyphs: [WritingGlyph] = []
        var renderedPreferences: WritingPreferences?
        private let onText: (String) -> Void
        private let onReplaceTail: (Int, String) -> Void
        private let onRejectedInput: (RejectedWritingInput) -> Void

        init(
            focusID: UUID,
            colorScheme: ColorScheme,
            textOpacity: Double,
            backspaceAllowed: Bool,
            onText: @escaping (String) -> Void,
            onReplaceTail: @escaping (Int, String) -> Void,
            onRejectedInput: @escaping (RejectedWritingInput) -> Void
        ) {
            self.focusID = focusID
            self.colorScheme = colorScheme
            self.textOpacity = textOpacity
            self.backspaceAllowed = backspaceAllowed
            self.onText = onText
            self.onReplaceTail = onReplaceTail
            self.onRejectedInput = onRejectedInput
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            let currentText = textView.text ?? ""
            let textLength = (currentText as NSString).length
            guard !replacement.isEmpty else {
                guard backspaceAllowed, let deletion = endDeletion(currentText: currentText, range: range) else {
                    onRejectedInput(.backspace)
                    return false
                }
                // The protocol only moves forward, so a permitted deletion
                // is recorded as a suffix rewrite: keep everything but the
                // new final character, then re-type that character.
                onReplaceTail(deletion.prefixCharacterCount, deletion.tailText)
                return false
            }

            guard !replacement.contains("\n"), !replacement.contains("\r") else {
                onRejectedInput(.enter)
                return false
            }

            if range.location == textLength, range.length == 0 {
                onText(replacement)
                return false
            }

            if let replacement = currentTailReplacement(
                currentText: currentText,
                range: range,
                replacement: replacement
            ) {
                onReplaceTail(replacement.prefixCharacterCount, replacement.tailText)
                return false
            }

            onRejectedInput(.backspace)
            return false
        }

        /// A deletion at the end of the text, expressed as a forward
        /// suffix-rewrite. Returns nil when the deletion is mid-text or
        /// would empty the page — the session must keep at least one
        /// written character.
        private func endDeletion(
            currentText: String,
            range: NSRange
        ) -> (prefixCharacterCount: Int, tailText: String)? {
            guard let swiftRange = Range(range, in: currentText) else {
                return nil
            }
            let proposed = currentText.replacingCharacters(in: swiftRange, with: "")
            guard !proposed.isEmpty,
                  proposed.count < currentText.count,
                  currentText.hasPrefix(proposed),
                  let lastCharacter = proposed.last else {
                return nil
            }
            return (proposed.count - 1, String(lastCharacter))
        }

        private func currentTailReplacement(
            currentText: String,
            range: NSRange,
            replacement: String
        ) -> (prefixCharacterCount: Int, tailText: String)? {
            guard let swiftRange = Range(range, in: currentText) else {
                return nil
            }

            let tailStart = currentTailStart(in: currentText)
            guard swiftRange.lowerBound >= tailStart else {
                return nil
            }

            let proposedText = currentText.replacingCharacters(in: swiftRange, with: replacement)
            let prefix = currentText[..<tailStart]
            guard proposedText.hasPrefix(prefix) else {
                return nil
            }

            let tailText = String(proposedText[tailStart...])
            guard !tailText.isEmpty,
                  tailText != currentText[tailStart...] else {
                return nil
            }

            return (prefix.count, tailText)
        }

        private func currentTailStart(in text: String) -> String.Index {
            guard let lastNonWhitespace = text.lastIndex(where: { !$0.isWhitespace }) else {
                return text.startIndex
            }

            let wordEnd = text.index(after: lastNonWhitespace)
            let searchable = text[..<wordEnd]
            if let boundary = searchable.lastIndex(where: \.isWhitespace) {
                return text.index(after: boundary)
            }
            return text.startIndex
        }
    }
}

private final class BottomRightAnchoredTextView: UITextView {
    private let minimumTopInset: CGFloat = 24
    private let leftInset: CGFloat = 24
    private var anchoredBottomInset: CGFloat = 24
    private var anchoredRightInset: CGFloat = 24
    var measurementLineSpacing: CGFloat = 0

    func updateAnchorInsets(bottom: CGFloat, right: CGFloat) {
        anchoredBottomInset = bottom
        anchoredRightInset = right
        updateTextContainerInsets()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextContainerInsets()
    }

    private func updateTextContainerInsets() {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let availableWidth = max(1, bounds.width - leftInset - anchoredRightInset)
        let textHeight = measuredTextHeight(width: availableWidth)
        let topInset = max(minimumTopInset, bounds.height - anchoredBottomInset - textHeight)
        let nextInsets = UIEdgeInsets(
            top: topInset,
            left: leftInset,
            bottom: anchoredBottomInset,
            right: anchoredRightInset
        )

        guard textContainerInset != nextInsets else {
            return
        }
        textContainerInset = nextInsets
    }

    func scrollToEndRespectingAnchor() {
        layoutManager.ensureLayout(for: textContainer)
        layoutIfNeeded()
        updateTextContainerInsets()
        layoutManager.ensureLayout(for: textContainer)
        layoutIfNeeded()

        let bottomOffset = max(
            -adjustedContentInset.top,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        if abs(contentOffset.y - bottomOffset) > 0.5 {
            setContentOffset(CGPoint(x: contentOffset.x, y: bottomOffset), animated: false)
        }
    }

    private func measuredTextHeight(width: CGFloat) -> CGFloat {
        guard let font else {
            return 0
        }
        guard !text.isEmpty else {
            return font.lineHeight
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = measurementLineSpacing
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
        return ceil(rect.height)
    }
}
