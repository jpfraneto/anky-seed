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
    @State private var appsOpenForDay = false
    @State private var targetMetToday = false
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
                .allowsHitTesting(acceptsWritingInput)
                .frame(width: geometry.size.width, height: textViewHeight)
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                // Words that rise behind the top chrome melt into the paper —
                // blurred and fading, still visibly there, never deleted. Below
                // the chrome's edge the page is untouched. The band reaches the
                // physical top of the screen (the GeometryReader is inset by the
                // safe area) so no seam shows under the status bar.
                let meltTopInset = geometry.safeAreaInsets.top
                let meltHeight = Self.chromeMeltHeight + meltTopInset
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.ankyPaper.opacity(0.78), Color.ankyPaper.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: (meltTopInset + Self.chromeMeltHeight * 0.7) / meltHeight),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geometry.size.width, height: meltHeight)
                    .position(x: geometry.size.width / 2, y: meltHeight / 2 - meltTopInset)
                    .allowsHitTesting(false)
                    .zIndex(18)

                WritingTopChrome(
                    state: writingPillState,
                    isPillInteractive: !viewModel.hasStarted,
                    timeText: timerText,
                    timeCaption: timerCaption,
                    silenceProgress: silenceProgress,
                    showsBackButton: !viewModel.hasStarted || viewModel.isWaitingToResumeContinuedDraft,
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
                .position(x: geometry.size.width / 2, y: 84)
                .zIndex(20)

                // The life-bar: the eight seconds of sealing silence made
                // visible, a hair above the keyboard. It surfaces after two
                // quiet seconds and drains right to left toward the seal.
                SilenceLifeBar(remaining: 1 - silenceProgress)
                    .frame(width: max(1, geometry.size.width - 48), height: 2)
                    .position(
                        x: geometry.size.width / 2,
                        y: max(14, keyboardTop - globalFrame.minY - 14)
                    )
                    .opacity(showsSilenceBar ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: showsSilenceBar)
                    .allowsHitTesting(false)
                    .zIndex(22)
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

                Image("anky-flow-writing-eyes")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 100)
                    .opacity(0.055)
                    .padding(.top, 8)
                    .padding(.trailing, -10)
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
            refreshOpenDayState()
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
                refreshOpenDayState()
                viewModel.prepareForWritingScene()
                viewModel.closeIfSilenceElapsed()
            } else {
                viewModel.persistOnBackground()
            }
        }
    }

    /// The pill must not promise a door that is already open: when the gate
    /// is off or a daily unlock is standing, the "opens the day" copy would
    /// be a lie. Read once per arrival, not per frame.
    private func refreshOpenDayState() {
        let now = Date()
        let unlockState = UnlockStateStore().load()
        appsOpenForDay = WriteBeforeScrollGateSwitchStore().isGateOff
            || (unlockState.grant?.tier == .daily && unlockState.isUnlocked(at: now))
        let calendar = Calendar.current
        let writtenTodayMs = SessionIndexStore().load()
            .filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
            .reduce(Int64(0)) { $0 + $1.durationMs }
        targetMetToday = writtenTodayMs >= DailyTargetStore().effectiveTargetMs(now: now)
    }

    /// The melt band covers the top chrome (156pt tall, centered at y 84 →
    /// bottom edge ~162) and releases the page fully a few lines below it.
    private static let chromeMeltHeight: CGFloat = 210

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
        // Apps already open for the day (gate off, an earlier unlock, or the
        // emergency breath): no door left to promise — say what is true.
        if appsOpenForDay || viewModel.hasAppliedPassiveDailyUnlockUpgrade {
            let metTarget = targetMetToday
                || viewModel.writeBeforeScrollSessionMetrics.hasDailyUnlockAvailable
                || viewModel.elapsedMs >= dailyTargetMs
            return metTarget ? .dayOpenTargetMet : .dayOpen
        }
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
        return viewModel.dailyUnlockEntitled ? .writingDailyOnly : .writingTargetOnly
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
        return min(1, max(0, Double(viewModel.silenceElapsedMs) / Double(writingPreferences.effectiveTerminalSilenceMs)))
    }

    /// The bar earns its place only once the writer has actually paused —
    /// two seconds in — and leaves the moment a key lands or the seal takes.
    private var showsSilenceBar: Bool {
        viewModel.hasStarted
            && viewModel.canAcceptInput
            && silenceProgress >= 0.25
            && silenceProgress < 1
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
    case writingTargetOnly
    case quick
    case daily
    /// Apps already open, daily target not yet written.
    case dayOpen
    /// Apps already open and today's target already met.
    case dayOpenTargetMet

    var title: String {
        switch self {
        case .empty:
            return "write one true thing"
        case .writing:
            return "finish a sentence · opens a 15-min pass"
        case .writingDailyOnly:
            return "write to your target · opens the day"
        case .writingTargetOnly:
            return "keep writing · it counts toward your target"
        case .quick:
            return "keep going for your daily target"
        case .daily:
            return "your apps are unlocked for the day"
        case .dayOpen:
            return "your apps are open · this writing is for you"
        case .dayOpenTargetMet:
            return "target met · your apps are unlocked for the day"
        }
    }

    /// The pigment each state washes the pill with.
    var tint: Color {
        switch self {
        case .empty, .writing, .writingDailyOnly, .writingTargetOnly:
            return .ankyGold
        case .quick:
            return .ankyApricot
        case .daily, .dayOpen:
            return .ankyViolet
        case .dayOpenTargetMet:
            return .ankySage
        }
    }

    /// The little glyph in the pill's leading medallion.
    var iconName: String {
        switch self {
        case .empty, .writing, .writingDailyOnly, .writingTargetOnly:
            return "lock"
        case .quick, .daily, .dayOpen, .dayOpenTargetMet:
            return "lock.open"
        }
    }
}

private struct WritingTopChrome: View {
    let state: WritingSessionPillState
    let isPillInteractive: Bool
    let timeText: String
    let timeCaption: String
    let silenceProgress: Double
    let showsBackButton: Bool
    let onBack: () -> Void
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Anky's eyes hold the center — she watches over the page.
                Image("anky-flow-writing-eyes")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .opacity(chromeOpacity)
                    .accessibilityHidden(true)

                HStack(alignment: .top) {
                    Group {
                        if showsBackButton {
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
                            .accessibilityLabel(AnkyLocalization.ui("Back"))
                        } else {
                            Color.clear
                                .frame(width: 40, height: 40)
                                .accessibilityHidden(true)
                        }
                    }
                    .opacity(chromeOpacity)

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
                isInteractive: isPillInteractive,
                opacity: chromeOpacity,
                onFocus: onFocus
            )
        }
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

            Text(AnkyLocalization.ui(state.title))
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
    case paste
}

/// A whisper of a line above the keyboard: full when a key just landed,
/// draining right to left through the configured terminal stillness.
private struct SilenceLifeBar: View {
    let remaining: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.ankyInk.opacity(0.05))
                Capsule()
                    .fill(Color.ankyUmber.opacity(0.34))
                    .frame(width: max(0, geometry.size.width * min(1, max(0, remaining))))
            }
        }
    }
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
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.keyboardDismissMode = .none
        textView.autocorrectionType = preferences.autocorrectEnabled ? .yes : .no
        textView.autocapitalizationType = .sentences
        // Spell-check stays off regardless of autocorrect: the red
        // underline reads as judgment on a page that never judges.
        textView.spellCheckingType = .no
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
        let currentGlyphs = glyphs
        let currentPreferences = preferences
        let currentColorScheme = colorScheme
        let currentTextOpacity = textOpacity
        let currentShouldFocus = shouldFocus
        let currentBottomInset = bottomInset
        let currentRightInset = rightInset
        let currentFocusID = focusID
        let lineSpacing = currentPreferences.textSize.pointSize * 0.42
        let renderedText = String(currentGlyphs.map(\.character))
        let font = currentPreferences.fontChoice.uiFont(size: currentPreferences.textSize.pointSize)
        let paragraph = Self.paragraphStyle(lineSpacing: lineSpacing)
        let typingForegroundColor = WritingRhythmColor.uiColor(progress: 0, alpha: 0.96, colorScheme: currentColorScheme)
        let paletteChanged = context.coordinator.colorScheme != colorScheme
            || context.coordinator.textOpacity != currentTextOpacity
        let preferencesChanged = context.coordinator.renderedPreferences != currentPreferences

        context.coordinator.isApplyingProgrammaticUpdate = true
        defer {
            context.coordinator.isApplyingProgrammaticUpdate = false
        }

        // The system keyboard applies valid edits natively (that is what
        // keeps autocorrect alive), so most updates find the text already
        // in place and only need the glyph pigments refreshed. A full
        // attributedText reset cancels the keyboard's autocorrect context —
        // it is reserved for genuine divergence (restore, rejected input).
        //
        // While the keyboard is mid-composition (inline prediction, QuickPath,
        // dictation, CJK) the view legitimately holds marked text the engine
        // has not seen — this pass runs on every ticker tick, and rewriting
        // the field then makes the keyboard re-commit its pending candidate
        // (the stray-short-word glitch). Leave the text alone; the diff sync
        // reconciles when the composition commits.
        let isComposing = uiView.markedTextRange != nil
        if isComposing {
            // Trait/inset upkeep below is still safe; text is not.
        } else if uiView.text != renderedText || preferencesChanged {
            uiView.font = font
            uiView.attributedText = makeAttributedText(
                glyphs: currentGlyphs,
                font: font,
                paragraph: paragraph,
                textOpacity: currentTextOpacity,
                colorScheme: currentColorScheme
            )
        } else if context.coordinator.renderedGlyphs != currentGlyphs || paletteChanged {
            applyGlyphAttributes(
                to: uiView,
                coordinator: context.coordinator,
                glyphs: currentGlyphs,
                font: font,
                paragraph: paragraph,
                textOpacity: currentTextOpacity,
                colorScheme: currentColorScheme,
                forceAll: paletteChanged
            )
        }
        context.coordinator.renderedGlyphs = currentGlyphs
        context.coordinator.colorScheme = currentColorScheme
        context.coordinator.textOpacity = currentTextOpacity
        context.coordinator.renderedPreferences = currentPreferences
        context.coordinator.lastSyncedText = renderedText
        context.coordinator.backspaceAllowed = currentPreferences.backspaceAllowed
        context.coordinator.acceptsInput = currentShouldFocus

        let autocorrection: UITextAutocorrectionType = currentPreferences.autocorrectEnabled ? .yes : .no
        if uiView.autocorrectionType != autocorrection {
            uiView.autocorrectionType = autocorrection
        }
        if uiView.spellCheckingType != .no {
            uiView.spellCheckingType = .no
        }
        uiView.typingAttributes = [
            .font: font,
            .foregroundColor: typingForegroundColor,
            .paragraphStyle: paragraph
        ]
        if let anchoredTextView = uiView as? BottomRightAnchoredTextView {
            anchoredTextView.measurementLineSpacing = lineSpacing
            anchoredTextView.updateAnchorInsets(bottom: currentBottomInset, right: currentRightInset)
        } else {
            uiView.textContainerInset.bottom = currentBottomInset
            uiView.textContainerInset.right = currentRightInset
        }
        uiView.verticalScrollIndicatorInsets.bottom = currentBottomInset
        uiView.contentInset = .zero

        if context.coordinator.focusID != currentFocusID {
            context.coordinator.focusID = currentFocusID
            if currentShouldFocus {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        }
        if currentShouldFocus, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !currentShouldFocus, uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }

        if !isComposing {
            context.coordinator.forceSelectionToEnd(of: uiView)
            if let anchoredTextView = uiView as? BottomRightAnchoredTextView {
                anchoredTextView.scrollToEndRespectingAnchor()
            } else {
                uiView.scrollRangeToVisible(NSRange(location: (uiView.text as NSString).length, length: 0))
            }
        }
    }

    /// Refreshes glyph pigments in place through the text storage — an
    /// attribute-only pass that never disturbs the keyboard's autocorrect
    /// state. Only glyphs whose color actually moved (plus the last two,
    /// whose "latest" emphasis shifts on every keystroke) are touched.
    private func applyGlyphAttributes(
        to uiView: UITextView,
        coordinator: Coordinator,
        glyphs: [WritingGlyph],
        font: UIFont,
        paragraph: NSParagraphStyle,
        textOpacity: Double,
        colorScheme: ColorScheme,
        forceAll: Bool
    ) {
        let storage = uiView.textStorage
        let latestIndex = glyphs.indices.last
        var utf16Location = 0

        storage.beginEditing()
        for index in glyphs.indices {
            let glyph = glyphs[index]
            let length = String(glyph.character).utf16.count
            defer { utf16Location += length }

            let previous = index < coordinator.renderedGlyphs.count ? coordinator.renderedGlyphs[index] : nil
            let nearEnd = index >= glyphs.count - 2
            guard forceAll || nearEnd || previous != glyph else {
                continue
            }
            guard utf16Location + length <= storage.length else {
                break
            }

            let isLatest = index == latestIndex
            let alpha = isLatest ? 0.96 : max(0.28, textOpacity * 0.82)
            storage.setAttributes(
                [
                    .font: font,
                    .foregroundColor: WritingRhythmColor.uiColor(progress: glyph.silenceProgress, alpha: alpha, colorScheme: colorScheme),
                    .paragraphStyle: paragraph
                ],
                range: NSRange(location: utf16Location, length: length)
            )
        }
        storage.endEditing()
    }

    private static func paragraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        return paragraph
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

    private func makeAttributedText(
        glyphs: [WritingGlyph],
        font: UIFont,
        paragraph: NSParagraphStyle,
        textOpacity: Double,
        colorScheme: ColorScheme
    ) -> NSAttributedString {
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
                        .font: font,
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
        /// Engine-truth text as of the last sync — the diff base for edits
        /// the system keyboard applies natively (typing, autocorrect).
        var lastSyncedText = ""
        var acceptsInput = false
        var isApplyingProgrammaticUpdate = false
        private var isForcingSelectionToEnd = false
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
            guard acceptsInput, !isApplyingProgrammaticUpdate else {
                return false
            }
            let currentText = textView.text ?? ""
            let textLength = (currentText as NSString).length

            // A composition commit (inline prediction, QuickPath, dictation,
            // CJK) replaces the marked range natively — let it land and let
            // the diff sync reconcile it afterward. Rejecting it here throws
            // away the writer's words and resets the keyboard's context.
            if textView.markedTextRange != nil {
                return !replacement.contains("\n") && !replacement.contains("\r")
            }

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

            // Valid insertions run natively and sync from the diff in
            // textViewDidChange — intercepting them (the old approach)
            // resets the keyboard's context after every keystroke, which is
            // what kept autocorrect from ever engaging.
            if range.location == textLength, range.length == 0 {
                guard replacement.count == 1 else {
                    onRejectedInput(.paste)
                    return false
                }
                return true
            }
            if isTailEdit(currentText: currentText, range: range) {
                return true
            }

            onRejectedInput(.backspace)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticUpdate, textView.markedTextRange == nil else {
                return // mid-composition (dictation, CJK): sync when it lands
            }
            let newText = textView.text ?? ""
            let oldText = lastSyncedText
            guard newText != oldText else {
                return
            }
            lastSyncedText = newText

            if newText.hasPrefix(oldText) {
                onText(String(newText.dropFirst(oldText.count)))
                return
            }

            // A native tail rewrite (autocorrect fixing the last word):
            // keep the common prefix, re-type the rest forward-only.
            let prefixCount = Self.commonPrefixCharacterCount(newText, oldText)
            let tail = String(newText.dropFirst(prefixCount))
            if !tail.isEmpty {
                onReplaceTail(prefixCount, tail)
            } else if prefixCount > 0 {
                // A pure native truncation slipped through: keep the page
                // non-empty by re-typing the final character.
                onReplaceTail(prefixCount - 1, String(newText.suffix(1)))
            } else {
                // Divergence with nothing to keep — the next update pass
                // rewrites the view from engine truth.
                onRejectedInput(.backspace)
            }
        }

        /// The caret lives at the end of the writing, always. Taps into the
        /// middle of the text do nothing — there is no going back.
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingProgrammaticUpdate, !isForcingSelectionToEnd, textView.markedTextRange == nil else {
                return
            }
            forceSelectionToEnd(of: textView)
        }

        func forceSelectionToEnd(of textView: UITextView) {
            let end = textView.endOfDocument
            guard let selected = textView.selectedTextRange else {
                textView.selectedTextRange = textView.textRange(from: end, to: end)
                return
            }
            guard !selected.isEmpty || textView.offset(from: selected.end, to: end) != 0 else {
                return
            }
            isForcingSelectionToEnd = true
            textView.selectedTextRange = textView.textRange(from: end, to: end)
            isForcingSelectionToEnd = false
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

        /// True when the edit stays within the last word — the range
        /// autocorrect rewrites when it fixes a typo.
        private func isTailEdit(currentText: String, range: NSRange) -> Bool {
            guard let swiftRange = Range(range, in: currentText) else {
                return false
            }
            return swiftRange.lowerBound >= currentTailStart(in: currentText)
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

        private static func commonPrefixCharacterCount(_ first: String, _ second: String) -> Int {
            var count = 0
            var firstIndex = first.startIndex
            var secondIndex = second.startIndex
            while firstIndex < first.endIndex,
                  secondIndex < second.endIndex,
                  first[firstIndex] == second[secondIndex] {
                count += 1
                firstIndex = first.index(after: firstIndex)
                secondIndex = second.index(after: secondIndex)
            }
            return count
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
