import SwiftUI
import UIKit

/// The writing page. One surface, two states: a live writing with the
/// keyboard up, or a finished one standing exactly where it was written. A
/// tap on a finished writing reopens it and the keyboard comes back.
struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyboardFrame: CGRect?
    @State private var lastObservedKeyboardHeight: CGFloat?
    /// The keyboard's last global top edge, held past dismissal so a finished
    /// writing keeps the identical bottom inset and the words never move.
    @State private var lastObservedKeyboardMinY: CGFloat?
    /// An anky is eight minutes. Always.
    private let dailyTargetMs = AnkyDuration.completeRitualMs
    let shouldFocus: Bool
    private let onCompleted: (SavedAnky) -> Void
    private let onOpenMenu: () -> Void

    init(
        viewModel: WriteViewModel,
        shouldFocus: Bool,
        onCompleted: @escaping (SavedAnky) -> Void,
        onOpenMenu: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.shouldFocus = shouldFocus
        self.onCompleted = onCompleted
        self.onOpenMenu = onOpenMenu
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let globalFrame = geometry.frame(in: .global)
                let shouldPreReserveKeyboard = shouldFocus && viewModel.canAcceptInput && keyboardFrame == nil
                let reservedKeyboard = reservedKeyboardHeight(
                    containerSize: geometry.size,
                    safeAreaBottom: geometry.safeAreaInsets.bottom
                )
                // A finished writing keeps the keyboard's EXACT top edge as
                // its bottom inset, so the words do not shift a pixel when
                // the keys withdraw.
                let keyboardTop: CGFloat = {
                    if isFinished {
                        return lastObservedKeyboardMinY ?? (globalFrame.maxY - reservedKeyboard)
                    }
                    if let minY = keyboardFrame?.minY {
                        return minY
                    }
                    return shouldPreReserveKeyboard ? globalFrame.maxY - reservedKeyboard : globalFrame.maxY
                }()
                let keyboardOverlap = max(0, globalFrame.maxY - keyboardTop)
                let keyboardIsVisible = keyboardTop < globalFrame.maxY
                let textBottomInset: CGFloat = keyboardOverlap + (keyboardIsVisible ? 24 : 36)
                let acceptsWritingInput = shouldFocus && viewModel.canAcceptInput

                ForwardOnlyTextView(
                    text: viewModel.displayedText,
                    focusID: viewModel.keyboardFocusID,
                    shouldFocus: acceptsWritingInput,
                    // The same view, finished: no input, free to scroll and
                    // select, and a tap reopens it.
                    isReadOnly: isFinished,
                    innerScrollEnabled: viewModel.hasStarted,
                    bottomInset: textBottomInset,
                    rightInset: 24,
                    colorScheme: colorScheme,
                    preferences: viewModel.preferences,
                    onText: acceptWritingInput,
                    onReplaceTail: { prefixCount, replacementText in
                        viewModel.replaceForwardTail(
                            keepingPrefixCharacterCount: prefixCount,
                            with: replacementText
                        )
                    },
                    onRejectedInput: { viewModel.nudgeInvalidInput($0) },
                    onTapWhileReadOnly: reopenFinishedWriting
                )
                .allowsHitTesting(acceptsWritingInput || isFinished)
                .frame(width: geometry.size.width, height: max(1, geometry.size.height))
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                // The keyboard's footprint, as quiet paper. On a finished
                // writing it is where the keys were: a tap there reopens it.
                let reserveTop = keyboardTop - globalFrame.minY
                let reserveHeight = max(1, globalFrame.maxY - keyboardTop
                    + geometry.safeAreaInsets.bottom)
                LinearGradient(
                    colors: [Color.ankyPaperDeep.opacity(0), Color.ankyPaperDeep.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: reserveHeight)
                .contentShape(Rectangle())
                .onTapGesture { reopenFinishedWriting() }
                .allowsHitTesting(isFinished)
                .position(x: geometry.size.width / 2, y: reserveTop + reserveHeight / 2)
                .zIndex(-1)

                // A finished writing: where the keys were, Anky offers the
                // two copies. It can be swiped down or closed; the paper
                // left behind still reopens the writing on a tap.
                let keysHeight = max(0, globalFrame.maxY - keyboardTop)
                if let finished = viewModel.completedArtifact, keysHeight > 120 {
                    AnkyHoldingTheWriting(
                        writing: finished.reconstructedText,
                        bottomInset: geometry.safeAreaInsets.bottom,
                        onTapPaper: reopenFinishedWriting
                    )
                        .id(finished.hash)
                        .frame(width: geometry.size.width, height: reserveHeight)
                        .position(x: geometry.size.width / 2, y: reserveTop + reserveHeight / 2)
                        .transition(.opacity)
                }

                // Words that rise behind the top chrome melt into the paper.
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
                                .init(color: .black, location: (meltTopInset + Self.chromeBottom) / meltHeight),
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

                AxisWritingTopBar(
                    timeText: timerText,
                    silenceProgress: silenceProgress,
                    isCompleted: isFinished,
                    showsMenu: showsMenuButton,
                    showsDone: viewModel.isContinuingFinishedWriting,
                    onOpenWritings: handleMenuTap,
                    onDone: handleDoneTap
                )
                .padding(.horizontal, 16)
                .frame(width: geometry.size.width, height: 44, alignment: .top)
                .position(x: geometry.size.width / 2, y: 6 + 22)
                .zIndex(20)

                // The sealing silence made visible: one bar resting on the
                // keyboard's top edge, surfacing after three quiet seconds.
                SilenceLifeBar(remaining: 1 - silenceProgress)
                    .frame(width: geometry.size.width, height: 5)
                    .position(
                        x: geometry.size.width / 2,
                        y: max(1, keyboardTop - globalFrame.minY - 2.5)
                    )
                    .opacity(showsSilenceBar ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: showsSilenceBar)
                    .allowsHitTesting(false)
                    .zIndex(22)
            }
        }
        .background {
            GeshtuWritingSurface(progress: writingSurfaceLightProgress)
                .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isFinished)
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
            viewModel.refreshPreferences()
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
        .onChange(of: isFinished) { finished in
            if finished { dismissKeyboard() }
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
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

    private var isFinished: Bool {
        viewModel.completedArtifact != nil
    }

    private func acceptWritingInput(_ text: String) {
        viewModel.accept(text)
    }

    /// Keep writing: the finished words become the live writing again.
    private func reopenFinishedWriting() {
        guard isFinished, viewModel.reopenFinishedSession() else { return }
        AnkyHaptics.light()
        viewModel.focusWritingKeyboard()
    }

    /// The top bar's bottom edge below the safe area (6pt inset + 44pt
    /// controls). The melt is full there and fades out just beneath it.
    private static let chromeBottom: CGFloat = 50
    private static let chromeMeltHeight: CGFloat = chromeBottom + 28

    // MARK: - The way out

    /// While the 8 second rule is holding a live writing, the way out is the
    /// stillness itself and the menu stays out of sight. A finished writing
    /// reopened to keep going has no rule, so the menu stays.
    private var showsMenuButton: Bool {
        isFinished || !viewModel.hasStarted || !viewModel.eightSecondRuleActive
    }

    /// The menu ends a live writing (it is saved and stays on the page) and
    /// slides the drawer in.
    private func handleMenuTap() {
        AnkyHaptics.light()
        viewModel.endWriting()
        dismissKeyboard()
        onOpenMenu()
    }

    /// ✓ on a writing reopened to keep going: it is finished again, saved
    /// with everything added.
    private func handleDoneTap() {
        AnkyHaptics.light()
        viewModel.endWriting()
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    /// Eight restrained steps let the display settle from rose toward cream.
    private var writingSurfaceLightProgress: Double {
        guard AnkyDuration.completeRitualMs > 0 else { return 1 }
        let completedMinutes = viewModel.elapsedMs / 60_000
        let ritualMinutes = max(1, AnkyDuration.completeRitualMs / 60_000)
        return min(1, max(0, Double(completedMinutes) / Double(ritualMinutes)))
    }

    /// One continuous clock: it counts down the eight minutes, then keeps
    /// reading the total time written.
    private var timerText: String {
        let remaining = dailyTargetMs - viewModel.elapsedMs
        if remaining > 0 {
            return AnkyDuration.clock(remaining)
        }
        return AnkyDuration.clock(viewModel.elapsedMs)
    }

    private var silenceProgress: Double {
        guard viewModel.eightSecondRuleActive else {
            return 0
        }
        return min(1, max(0, Double(viewModel.silenceElapsedMs) / Double(AnkyDuration.defaultTerminalSilenceMs)))
    }

    /// The line earns its place only once the writer has paused three
    /// seconds, and leaves the moment a key lands or the seal takes.
    private var showsSilenceBar: Bool {
        viewModel.eightSecondRuleActive
            && viewModel.hasStarted
            && viewModel.canAcceptInput
            && viewModel.silenceElapsedMs >= 3000
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
                lastObservedKeyboardMinY = frame.minY
            }
        }

        let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        let animation = Animation.easeOut(duration: max(0.16, duration ?? 0.24))
        withAnimation(animation) {
            keyboardFrame = frame
        }
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

/// The writing page's chrome: the menu on the left, the clock on the right.
/// The clock only tells time; an anky is always eight minutes. On a writing
/// reopened to keep going, ✓ stands where the clock was.
private struct AxisWritingTopBar: View {
    let timeText: String
    let silenceProgress: Double
    /// The writing has ended: the clock steps aside and the top-right belongs
    /// to the finished writing's own controls.
    let isCompleted: Bool
    let showsMenu: Bool
    let showsDone: Bool
    let onOpenWritings: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if showsMenu {
                Button(action: onOpenWritings) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(width: 44, height: 44)
                        .ankyGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AnkyLocalization.ui("Your writings"))
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            if showsDone, !isCompleted {
                Button(action: onDone) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(width: 44, height: 44)
                        .ankyGlass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AnkyLocalization.ui("Done writing"))
                .transition(.opacity)
            } else if !isCompleted {
                Text(timeText)
                    .font(.system(size: 17, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.ankyInkSoft)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .ankyGlass(in: Capsule())
                    .accessibilityLabel(AnkyLocalization.ui("Writing time %@", timeText))
            }
        }
        .frame(minHeight: 44)
        // Finished, the bar returns to full presence; live, it recedes as
        // the silence gathers.
        .opacity(isCompleted ? 1 : chromeOpacity)
        .animation(.easeInOut(duration: 0.4), value: isCompleted)
        .animation(.easeInOut(duration: 0.3), value: showsMenu)
        .animation(.easeInOut(duration: 0.3), value: showsDone)
        .animation(.linear(duration: 0.1), value: silenceProgress)
    }

    private var chromeOpacity: Double {
        max(0.28, 1 - min(1, max(0, silenceProgress)) * 0.72)
    }
}

/// What the page refuses: going back, new lines, pasting.
enum RejectedWritingInput {
    case backspace
    case enter
    case paste
}

/// A plain text view: one font, one ink, the writing in it as-is. It only
/// refuses what the ritual refuses (going back, pasting, new lines).
private struct ForwardOnlyTextView: UIViewRepresentable {
    let text: String
    let focusID: UUID
    let shouldFocus: Bool
    /// The writing has ended: the same view, now unwritable and free to
    /// scroll. Its words never move to another view (spec §13).
    let isReadOnly: Bool
    /// False on the device's blank page: the pan then belongs to the put-down
    /// flick that recedes the device into the Anchor (device split,
    /// 2026-07-22). Flips true with the first keystroke.
    let innerScrollEnabled: Bool
    let bottomInset: CGFloat
    let rightInset: CGFloat
    let colorScheme: ColorScheme
    let preferences: WritingPreferences
    let onText: (String) -> Void
    let onReplaceTail: (Int, String) -> Void
    let onRejectedInput: (RejectedWritingInput) -> Void
    /// A tap on a finished writing: keep writing.
    let onTapWhileReadOnly: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.adjustsFontForContentSizeCategory = false
        textView.tintColor = UIColor(Color.ankyUmber)
        textView.keyboardAppearance = colorScheme == .dark ? .dark : .light
        textView.textAlignment = .left
        textView.isEditable = !isReadOnly
        textView.isUserInteractionEnabled = true
        textView.keyboardDismissMode = .interactive
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
        textView.textContainerInset = UIEdgeInsets(top: Self.topInset, left: 24, bottom: 0, right: rightInset)
        textView.contentInset.bottom = bottomInset
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
        textView.isScrollEnabled = innerScrollEnabled || isReadOnly
        // Interactive dismissal needs the pan to engage even while the page
        // is shorter than the screen.
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = false
        Self.applyStyle(to: textView, text: text, preferences: preferences, colorScheme: colorScheme)
        context.coordinator.lastSyncedText = text
        context.coordinator.renderedPreferences = preferences

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleReadOnlyTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        if shouldFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    /// The first line starts below the top bar and its melt.
    static let topInset: CGFloat = 80

    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        let scrollEnabled = innerScrollEnabled || isReadOnly
        if uiView.isScrollEnabled != scrollEnabled {
            uiView.isScrollEnabled = scrollEnabled
        }
        if uiView.isEditable == isReadOnly {
            uiView.isEditable = !isReadOnly
        }
        coordinator.isReadOnly = isReadOnly
        coordinator.onTapWhileReadOnly = onTapWhileReadOnly
        coordinator.backspaceAllowed = preferences.backspaceAllowed
        coordinator.acceptsInput = shouldFocus

        let keyboardAppearance: UIKeyboardAppearance = colorScheme == .dark ? .dark : .light
        if uiView.keyboardAppearance != keyboardAppearance {
            uiView.keyboardAppearance = keyboardAppearance
            if uiView.isFirstResponder { uiView.reloadInputViews() }
        }
        let autocorrection: UITextAutocorrectionType = preferences.autocorrectEnabled ? .yes : .no
        if uiView.autocorrectionType != autocorrection {
            uiView.autocorrectionType = autocorrection
        }

        // The keyboard types straight into the view, so most updates find the
        // text already there and do nothing. The view is only rewritten when
        // the engine disagrees (a refused key, a restore, a new page) or the
        // look changed. Never mid-composition (dictation, QuickPath, CJK).
        let isComposing = uiView.markedTextRange != nil
        let styleChanged = coordinator.renderedPreferences != preferences
            || coordinator.colorScheme != colorScheme
        if !isComposing, styleChanged || text != coordinator.lastSyncedText {
            coordinator.isApplyingProgrammaticUpdate = true
            Self.applyStyle(to: uiView, text: text, preferences: preferences, colorScheme: colorScheme)
            coordinator.isApplyingProgrammaticUpdate = false
            coordinator.lastSyncedText = text
            coordinator.renderedPreferences = preferences
            coordinator.colorScheme = colorScheme
            if !isReadOnly {
                coordinator.forceSelectionToEnd(of: uiView)
                coordinator.scrollToCaret(uiView)
            }
        }

        if uiView.textContainerInset.right != rightInset {
            uiView.textContainerInset.right = rightInset
        }
        if uiView.contentInset.bottom != bottomInset {
            uiView.contentInset.bottom = bottomInset
            uiView.verticalScrollIndicatorInsets.bottom = bottomInset
            if !isReadOnly { coordinator.scrollToCaret(uiView) }
        }

        if coordinator.focusID != focusID {
            coordinator.focusID = focusID
            if shouldFocus {
                // An explicit summons (tap the pill, a fresh scene) always
                // outranks a prior push-away.
                coordinator.keyboardPushedAway = false
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            }
        }
        if shouldFocus, !uiView.isFirstResponder, !coordinator.keyboardPushedAway {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !shouldFocus, uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    /// One font, one ink, one line spacing for the whole writing.
    private static func attributes(
        preferences: WritingPreferences,
        colorScheme: ColorScheme
    ) -> [NSAttributedString.Key: Any] {
        let size = preferences.textSize.pointSize
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = size * 0.42
        return [
            .font: preferences.fontChoice.uiFont(size: size),
            .foregroundColor: preferences.inkChoice.uiColor(colorScheme: colorScheme, alpha: 0.96),
            .paragraphStyle: paragraph
        ]
    }

    private static func applyStyle(
        to textView: UITextView,
        text: String,
        preferences: WritingPreferences,
        colorScheme: ColorScheme
    ) {
        let attributes = attributes(preferences: preferences, colorScheme: colorScheme)
        textView.attributedText = NSAttributedString(string: text, attributes: attributes)
        textView.typingAttributes = attributes
        textView.tintColor = preferences.inkChoice.uiColor(colorScheme: colorScheme)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            focusID: focusID,
            colorScheme: colorScheme,
            backspaceAllowed: preferences.backspaceAllowed,
            onText: onText,
            onReplaceTail: onReplaceTail,
            onRejectedInput: onRejectedInput
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var focusID: UUID
        var colorScheme: ColorScheme
        var backspaceAllowed: Bool
        var renderedPreferences: WritingPreferences?
        /// Engine-truth text as of the last sync — the diff base for edits
        /// the system keyboard applies natively (typing, autocorrect).
        var lastSyncedText = ""
        var acceptsInput = false
        /// The writing is finished: the page belongs to the reader now — the
        /// anchoring, the forced caret and the refusals all stand down.
        var isReadOnly = false
        var isApplyingProgrammaticUpdate = false
        var onTapWhileReadOnly: () -> Void = {}
        /// The writer pushed the keyboard away (the interactive drag past
        /// it). While true, the update pass must not summon it back — only a
        /// tap on the page or an explicit focus request clears it.
        var keyboardPushedAway = false
        private var isForcingSelectionToEnd = false
        private let onText: (String) -> Void
        private let onReplaceTail: (Int, String) -> Void
        private let onRejectedInput: (RejectedWritingInput) -> Void

        init(
            focusID: UUID,
            colorScheme: ColorScheme,
            backspaceAllowed: Bool,
            onText: @escaping (String) -> Void,
            onReplaceTail: @escaping (Int, String) -> Void,
            onRejectedInput: @escaping (RejectedWritingInput) -> Void
        ) {
            self.focusID = focusID
            self.colorScheme = colorScheme
            self.backspaceAllowed = backspaceAllowed
            self.onText = onText
            self.onReplaceTail = onReplaceTail
            self.onRejectedInput = onRejectedInput
        }

        /// A tap on a finished page reopens it — unless a passage is
        /// selected, when the tap only clears the selection.
        @objc func handleReadOnlyTap(_ recognizer: UITapGestureRecognizer) {
            guard isReadOnly, recognizer.state == .ended,
                  let textView = recognizer.view as? UITextView else { return }
            guard textView.selectedRange.length == 0 else { return }
            onTapWhileReadOnly()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            keyboardPushedAway = false
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // While input is accepted, only the writer ends editing — the
            // interactive dismissal (or the system) took the keyboard, and it
            // must stay down until asked back. Programmatic resigns happen
            // only when input is no longer accepted.
            if acceptsInput {
                keyboardPushedAway = true
            }
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
                guard backspaceAllowed else {
                    onRejectedInput(.backspace)
                    return false
                }
                guard let deletion = endDeletion(currentText: currentText, range: range) else {
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
            scrollToCaret(textView)

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
            // Once finished, the writer may select any range they like — that
            // is how a passage is copied out of the page.
            guard !isReadOnly,
                  !isApplyingProgrammaticUpdate,
                  !isForcingSelectionToEnd,
                  textView.markedTextRange == nil else {
                return
            }
            forceSelectionToEnd(of: textView)
        }

        /// Keeps the end of the writing above the keyboard.
        func scrollToCaret(_ textView: UITextView) {
            guard !textView.isTracking, !textView.isDragging, !textView.isDecelerating else { return }
            textView.scrollRangeToVisible(textView.selectedRange)
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

// MARK: - Anky, offering the copies

/// A finished writing: Anky comes into the space the keys left, holding the
/// page, with the two copies. A swipe down or the × sends it away.
private struct AnkyHoldingTheWriting: View {
    let writing: String
    let bottomInset: CGFloat
    let onTapPaper: () -> Void

    private enum Copy { case withPrompt, withoutPrompt }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var dismissed = false
    @State private var dragOffset: CGFloat = 0
    @State private var breathes = false
    @State private var copied: Copy?

    var body: some View {
        GeometryReader { geometry in
            let figureHeight = max(72, min(156, geometry.size.height - bottomInset - 150))
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Image("anky-recover-writing")
                        .resizable()
                        .scaledToFit()
                        .frame(height: figureHeight)
                        .scaleEffect(breathes ? 1.012 : 1, anchor: .bottom)
                        .accessibilityHidden(true)

                    Button { copy(.withPrompt) } label: {
                        Text(AnkyLocalization.ui(copied == .withPrompt ? "anky: copied" : "anky: copy with prompt"))
                            .font(.fraunces(17, weight: .regular))
                            .foregroundStyle(copied == .withPrompt ? Color.ankySage : Color.ankyInk)
                            .padding(.horizontal, 26)
                            .frame(minHeight: 48)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .ankyGlass(in: Capsule(), interactive: true)

                    Button { copy(.withoutPrompt) } label: {
                        Text(AnkyLocalization.ui(copied == .withoutPrompt ? "anky: copied" : "anky: copy without prompt"))
                            .font(.fraunces(15, weight: .light))
                            .foregroundStyle(copied == .withoutPrompt ? Color.ankySage : Color.ankyInkSoft)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, bottomInset)
                .animation(.easeInOut(duration: 0.25), value: copied)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ankyInkSoft)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .padding(.trailing, 12)
                .accessibilityLabel(AnkyLocalization.ui("anky: close"))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Anky's own patch of paper: a long writing passes beneath it,
            // softly, the way words melt under the top chrome.
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.ankyPaper.opacity(0.72))
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapPaper() }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 70 || value.predictedEndTranslation.height > 160 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragOffset = 0 }
                        }
                    }
            )
        }
        .offset(y: (arrived || reduceMotion ? 0 : 14) + dragOffset + (dismissed ? 60 : 0))
        .opacity(dismissed ? 0 : (arrived ? 1 : 0))
        .allowsHitTesting(!dismissed)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.4 : 0.9).delay(0.3)) {
                arrived = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true).delay(1.2)) {
                breathes = true
            }
        }
    }

    private func dismiss() {
        AnkyHaptics.light()
        withAnimation(.easeOut(duration: 0.32)) {
            dismissed = true
        }
    }

    private func copy(_ kind: Copy) {
        let text = kind == .withPrompt ? AnkyReflectionPrompt.build(from: writing) : writing
        ClipboardClient().copy(text)
        AnkyHaptics.light()
        copied = kind
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if copied == kind { copied = nil }
        }
    }
}
