import SwiftUI
import UIKit

struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardFrame: CGRect?
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
                let keyboardTop = keyboardFrame?.minY ?? globalFrame.maxY
                let visibleHeight = max(1, min(globalFrame.maxY, keyboardTop) - globalFrame.minY)
                let keyboardIsVisible = keyboardTop < globalFrame.maxY
                let textViewBottomGap: CGFloat = keyboardIsVisible ? 8 : 0
                let textViewHeight = max(1, visibleHeight - textViewBottomGap)
                let ringSize = RitualRingsView.size
                let ringRadius = ringSize / 2
                let ringCenter = CGPoint(
                    x: max(ringRadius + 8, geometry.size.width - ringRadius - 8),
                    y: max(ringRadius + 8, visibleHeight - textViewBottomGap - ringRadius)
                )
                let textViewWidth = max(1, ringCenter.x - ringRadius - 8)
                let acceptsWritingInput = shouldFocus && viewModel.canAcceptInput

                ForwardOnlyTextView(
                    glyphs: viewModel.displayedGlyphs,
                    focusID: viewModel.keyboardFocusID,
                    shouldFocus: acceptsWritingInput,
                    bottomInset: 8,
                    rightInset: 14,
                    textOpacity: pageTextOpacity,
                    onCharacter: viewModel.accept,
                    onRejectedInput: viewModel.nudgeInvalidInput
                )
                .frame(width: textViewWidth, height: textViewHeight)
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)

                if viewModel.shouldShowRitualRing {
                    RitualRingsView(
                        elapsedMs: viewModel.elapsedMs,
                        silenceElapsedMs: viewModel.silenceElapsedMs,
                        lastCharacter: viewModel.lastCharacter,
                        lastCharacterColor: activeRhythmColor,
                        pulseID: viewModel.lastCharacterPulseID,
                        isRitualComplete: viewModel.hasReachedRitualMark
                    )
                    .position(ringCenter)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }

                if viewModel.hasReachedRitualMark {
                    Text(AnkyDuration.clock(viewModel.elapsedMs))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Color(.systemBackground).opacity(0.64), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                        )
                        .position(
                            x: ringCenter.x,
                            y: max(16, ringCenter.y - ringRadius - 24)
                        )
                        .accessibilityLabel("Writing time \(AnkyDuration.clock(viewModel.elapsedMs))")
                        .transition(.opacity)
                }
            }

        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.keyboard)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(viewModel.shouldShowTopActions ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if showsMapButton {
                    Button {
                        viewModel.clearCurrentSession()
                        onCloseToMap()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Open Map")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.hasActiveDotAnky && viewModel.canBeginNewPage {
                    Button {
                        viewModel.clearCurrentSession()
                    } label: {
                        Image(systemName: "doc")
                    }
                    .accessibilityLabel("Begin a new page")
                } else if !viewModel.hasActiveDotAnky {
                    WriteToolbarPasteButton(
                        paste: pasteArtifact,
                        devPaste: devPasteArtifact
                    )
                }
            }
        }
        .statusBarHidden(!viewModel.shouldShowTopActions)
        .persistentSystemOverlays(viewModel.shouldShowTopActions ? .visible : .hidden)
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
            keyboardFrame = nil
        }
        .onAppear {
            viewModel.bindCompletion(onCompleted)
            if shouldFocus {
                viewModel.prepareForWritingScene()
            }
            viewModel.closeIfSilenceElapsed()
        }
        .onChange(of: shouldFocus) { _, isFocused in
            if isFocused {
                viewModel.prepareForWritingScene()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, shouldFocus {
                viewModel.prepareForWritingScene()
                viewModel.closeIfSilenceElapsed()
            } else {
                viewModel.persistOnBackground()
            }
        }
    }

    private func pasteArtifact() {
        _ = viewModel.importAnkyArtifact(viewModel.clipboardText() ?? "")
    }

    private func devPasteArtifact() {
        _ = viewModel.importAnkyArtifact(viewModel.devSampleAnkyArtifact)
    }

    private var pageTextOpacity: Double {
        let resolveProgress = min(1, max(0, Double(viewModel.silenceElapsedMs - 3000) / 5000))
        return 0.22 + resolveProgress * 0.78
    }

    private var activeRhythmColor: Color {
        WritingRhythmColor.color(progress: latestCharacterColorProgress)
    }

    private var latestCharacterColorProgress: Double {
        min(1, max(0, Double(viewModel.silenceElapsedMs) / Double(AnkyDuration.terminalSilenceMs)))
    }

    private var showsMapButton: Bool {
        !viewModel.hasActiveDotAnky || viewModel.isPausedOnDraft || viewModel.completedArtifact != nil
    }

    private func updateKeyboardFrame(from notification: Notification) {
        keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    }

}

private struct WriteToolbarPasteButton: View {
    let paste: () -> Void
    let devPaste: () -> Void

    var body: some View {
        Button(action: paste) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 15, weight: .regular))
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 5)
                .onEnded { _ in devPaste() }
        )
        .accessibilityLabel("Paste .anky artifact")
        .accessibilityHint("Hold for five seconds to paste the built-in dev .anky")
    }
}

private enum WritingRhythmColor {
    static func color(progress: Double) -> Color {
        let clamped = min(1, max(0, progress))
        let red = 1.0 + (0.94 - 1.0) * clamped
        let green = 1.0 + (0.12 - 1.0) * clamped
        let blue = 1.0 + (0.08 - 1.0) * clamped
        return Color(red: red, green: green, blue: blue)
    }

    static func uiColor(progress: Double, alpha: Double = 1) -> UIColor {
        UIColor(color(progress: progress)).withAlphaComponent(alpha)
    }
}

private struct RitualRingsView: View {
    static let size: CGFloat = 106
    private static let ringDiameter: CGFloat = 88
    private static let silenceDiameter: CGFloat = 58

    let elapsedMs: Int64
    let silenceElapsedMs: Int64
    let lastCharacter: Character?
    let lastCharacterColor: Color
    let pulseID: UUID
    let isRitualComplete: Bool

    private let colors: [Color] = [
        Color(red: 0.91, green: 0.20, blue: 0.14),
        Color(red: 0.95, green: 0.48, blue: 0.10),
        Color(red: 0.96, green: 0.81, blue: 0.22),
        Color(red: 0.22, green: 0.72, blue: 0.26),
        Color(red: 0.10, green: 0.39, blue: 0.95),
        Color(red: 0.30, green: 0.25, blue: 0.80),
        Color(red: 0.58, green: 0.24, blue: 0.90),
        Color(red: 0.96, green: 0.95, blue: 0.87)
    ]

    private var minuteProgress: Double {
        min(8, max(0, ritualProgress * 8))
    }

    private var ritualProgress: Double {
        min(1, Double(elapsedMs) / Double(AnkyDuration.completeRitualMs))
    }

    private var silenceProgress: Double {
        min(1, max(0, Double(silenceElapsedMs - 3000) / 5000))
    }

    private var remainingSilenceSeconds: Int {
        max(0, Int(ceil(Double(AnkyDuration.terminalSilenceMs - silenceElapsedMs) / 1000)))
    }

    private func segmentProgress(_ index: Int) -> Double {
        min(1, max(0, minuteProgress - Double(index)))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breath = (sin(time * 2.2) + 1) / 2

            ZStack {
                if isRitualComplete {
                    let completePulse = (sin(time * 3.2) + 1) / 2
                    Circle()
                        .stroke(
                            AnkyTheme.gold.opacity(0.24 + completePulse * 0.36),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .frame(width: Self.ringDiameter + 14, height: Self.ringDiameter + 14)
                        .shadow(color: AnkyTheme.gold.opacity(0.36 + completePulse * 0.24), radius: 9 + completePulse * 5)
                        .shadow(color: Color.white.opacity(0.14 + completePulse * 0.14), radius: 4 + completePulse * 3)
                        .transition(.opacity)
                }

                Circle()
                    .fill(Color(red: 0.035, green: 0.024, blue: 0.016).opacity(0.94))
                    .frame(width: Self.ringDiameter + 12, height: Self.ringDiameter + 12)
                    .shadow(color: Color.black.opacity(0.72), radius: 8, y: 2)

                Circle()
                    .stroke(AnkyTheme.gold.opacity(0.20), lineWidth: 1)
                    .frame(width: Self.ringDiameter + 8, height: Self.ringDiameter + 8)

                Circle()
                    .fill(Color(red: 0.06, green: 0.047, blue: 0.037).opacity(0.98))
                    .frame(width: Self.ringDiameter - 22, height: Self.ringDiameter - 22)

                ZStack {
                    ForEach(colors.indices, id: \.self) { index in
                        let progress = segmentProgress(index)
                        let isPassed = progress >= 1
                        let isActive = progress > 0 && progress < 1
                        let activeWidth: CGFloat = isPassed ? 13 : (isActive ? 11 : 7)

                        GradientRingSegment(
                            index: index,
                            progress: 1,
                            startColor: colors[index].opacity(0.22),
                            endColor: colors[index].opacity(0.22),
                            lineWidth: 6,
                            diameter: Self.ringDiameter
                        )

                        if progress > 0 {
                            GradientRingSegment(
                                index: index,
                                progress: progress,
                                startColor: colors[index].opacity(isActive ? 0.76 : 0.92),
                                endColor: colors[index].opacity(isActive ? 0.76 : 0.92),
                                lineWidth: activeWidth + (isActive ? breath * 1.2 : 0),
                                diameter: Self.ringDiameter
                            )
                            .shadow(color: colors[index].opacity(isActive ? 0.34 : 0.20), radius: isActive ? 4 : 2)
                        }
                    }
                }

                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .fill(Color.black.opacity(0.56))
                        .frame(width: 2, height: 15)
                        .offset(y: -Self.ringDiameter / 2)
                        .rotationEffect(.degrees(Double(index) * 45 + 22.5))
                        .shadow(color: Color.black.opacity(0.34), radius: 1)
                }

                Circle()
                    .stroke(AnkyTheme.gold.opacity(0.24), lineWidth: 1.5)
                    .frame(width: Self.silenceDiameter + 7, height: Self.silenceDiameter + 7)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.10 + breath * 0.04),
                                AnkyTheme.gold.opacity(0.08),
                                Color.black.opacity(0.78),
                                Color.black.opacity(0.96)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.24),
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: Self.silenceDiameter, height: Self.silenceDiameter)

                if silenceElapsedMs >= 3000 {
                    Text("\(remainingSilenceSeconds)")
                        .font(.system(size: 25, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AnkyTheme.gold.opacity(0.88))
                        .contentTransition(.numericText())
                } else if let lastCharacter {
                    Text(String(lastCharacter))
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(lastCharacterColor.opacity(0.88))
                        .id(pulseID)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                } else if elapsedMs == 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(sin(time * 3.4) > 0 ? 0.58 : 0.20))
                        .frame(width: 2, height: 25)
                }

                Circle()
                    .trim(from: 0, to: silenceProgress)
                    .stroke(
                        Color.white.opacity(0.34 + breath * 0.16),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: Self.silenceDiameter, height: Self.silenceDiameter)
                    .opacity(silenceElapsedMs >= 3000 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: silenceElapsedMs >= 3000)
                    .animation(.linear(duration: 0.04), value: silenceProgress)
            }
            .frame(width: Self.size, height: Self.size)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeInOut(duration: 0.4), value: isRitualComplete)
        .allowsHitTesting(false)
    }
}

private enum PortalPalette {
    static let bronzeGradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.77, blue: 0.42),
            Color(red: 0.54, green: 0.33, blue: 0.15),
            Color(red: 0.87, green: 0.67, blue: 0.33),
            Color(red: 0.24, green: 0.14, blue: 0.07)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct PortalProgressCursor: View {
    let progress: Double
    let diameter: CGFloat
    let isComplete: Bool
    let breath: Double

    var body: some View {
        let clampedProgress = min(1, max(0, progress))
        let angle = (-Double.pi / 2) + clampedProgress * Double.pi * 2
        let radius = diameter / 2
        let offset = CGSize(
            width: cos(angle) * radius,
            height: sin(angle) * radius
        )

        ZStack {
            Circle()
                .fill(Color.white.opacity(0.86))
                .frame(width: 6.5 + breath * 2.0, height: 6.5 + breath * 2.0)
                .shadow(color: Color.white.opacity(0.66), radius: 5)
                .shadow(color: AnkyTheme.gold.opacity(0.58), radius: 8)

            Circle()
                .stroke(AnkyTheme.gold.opacity(0.74), lineWidth: 1)
                .frame(width: 13 + breath * 5, height: 13 + breath * 5)
        }
        .offset(offset)
        .opacity(clampedProgress > 0 || isComplete ? 1 : 0)
    }
}

private struct GradientRingSegment: View {
    let index: Int
    let progress: Double
    let startColor: Color
    let endColor: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        let segmentStart = Double(index) / 8
        let segmentEnd = Double(index + 1) / 8
        let gap = 0.006
        let start = segmentStart + gap
        let fullEnd = segmentEnd - gap
        let end = start + (fullEnd - start) * min(1, max(0, progress))
        Circle()
            .trim(from: start, to: max(start + 0.0001, end))
            .stroke(
                AngularGradient(
                    colors: [startColor, endColor],
                    center: .center,
                    startAngle: .degrees(segmentStart * 360 - 90),
                    endAngle: .degrees(segmentEnd * 360 - 90)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
    }
}

private struct ForwardOnlyTextView: UIViewRepresentable {
    let glyphs: [WritingGlyph]
    let focusID: UUID
    let shouldFocus: Bool
    let bottomInset: CGFloat
    let rightInset: CGFloat
    let textOpacity: Double
    let onCharacter: (Character) -> Void
    let onRejectedInput: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = BottomRightAnchoredTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .regular)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UIColor.label.withAlphaComponent(textOpacity)
        textView.tintColor = .clear
        textView.textAlignment = .right
        textView.isEditable = shouldFocus
        textView.keyboardDismissMode = .none
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
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
        if context.coordinator.renderedGlyphs != glyphs || uiView.text != renderedText {
            uiView.attributedText = makeAttributedText(font: uiView.font)
            context.coordinator.renderedGlyphs = glyphs
        }
        uiView.textColor = UIColor.label.withAlphaComponent(textOpacity)
        uiView.backgroundColor = .clear
        uiView.isEditable = shouldFocus
        if let anchoredTextView = uiView as? BottomRightAnchoredTextView {
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
        Coordinator(focusID: focusID, onCharacter: onCharacter, onRejectedInput: onRejectedInput)
    }

    private func makeAttributedText(font: UIFont?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byWordWrapping

        let textFont = font ?? UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .regular)
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
                        .foregroundColor: WritingRhythmColor.uiColor(progress: glyph.silenceProgress, alpha: alpha),
                        .paragraphStyle: paragraph
                    ]
                )
            )
        }

        return attributed
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var focusID: UUID
        var renderedGlyphs: [WritingGlyph] = []
        private let onCharacter: (Character) -> Void
        private let onRejectedInput: () -> Void

        init(
            focusID: UUID,
            onCharacter: @escaping (Character) -> Void,
            onRejectedInput: @escaping () -> Void
        ) {
            self.focusID = focusID
            self.onCharacter = onCharacter
            self.onRejectedInput = onRejectedInput
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard range.length == 0,
                  replacement.count == 1,
                  let character = replacement.first,
                  character != "\n",
                  character != "\r" else {
                if range.length > 0 || replacement == "\n" || replacement == "\r" {
                    onRejectedInput()
                }
                return false
            }

            onCharacter(character)
            return false
        }
    }
}

private final class BottomRightAnchoredTextView: UITextView {
    private let minimumTopInset: CGFloat = 24
    private let leftInset: CGFloat = 24
    private var anchoredBottomInset: CGFloat = 24
    private var anchoredRightInset: CGFloat = 24

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
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byWordWrapping
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
