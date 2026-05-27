import SwiftUI
import UIKit

struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardFrame: CGRect?
    @State private var confirmClearDotAnky = false
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
                let surfaceBottomInset: CGFloat = keyboardIsVisible ? 12 : 24
                let textViewHeight = visibleHeight
                let contentBottomY = max(24, visibleHeight - surfaceBottomInset)
                let ringSize = RitualRingsView.size
                let ringRadius = ringSize / 2
                let textAnchor = CGPoint(
                    x: max(24, geometry.size.width - (ringSize + 30)),
                    y: contentBottomY
                )
                let ringCenter = CGPoint(
                    x: max(ringRadius + 8, geometry.size.width - ringRadius - 8),
                    y: max(ringRadius + 8, contentBottomY - ringRadius)
                )

                ForwardOnlyTextView(
                    glyphs: viewModel.displayedGlyphs,
                    focusID: viewModel.keyboardFocusID,
                    shouldFocus: shouldFocus,
                    bottomInset: max(surfaceBottomInset, textViewHeight - textAnchor.y),
                    rightInset: max(14, geometry.size.width - (ringCenter.x - ringRadius - 10)),
                    textOpacity: pageTextOpacity,
                    onCharacter: viewModel.accept,
                    onRejectedInput: viewModel.nudgeInvalidInput
                )
                .frame(width: geometry.size.width, height: textViewHeight)
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

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
                VStack {
                    HStack {
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
                            .accessibilityLabel("Writing time \(AnkyDuration.clock(viewModel.elapsedMs))")

                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 12)
                .padding(.leading, 14)
                .transition(.opacity)
            }

            WriteTopActionBar(
                isVisible: viewModel.shouldShowTopActions,
                hasActiveDotAnky: viewModel.hasActiveDotAnky,
                canBeginNewPage: viewModel.canBeginNewPage,
                openMap: {
                    viewModel.abandonIfEmpty()
                    onCloseToMap()
                },
                paste: pasteArtifact,
                devPaste: devPasteArtifact,
                clear: {
                    confirmClearDotAnky = true
                }
            )
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.keyboard)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardFrame = nil
        }
        .confirmationDialog("begin a new page?", isPresented: $confirmClearDotAnky, titleVisibility: .visible) {
            Button("begin a new page", role: .destructive) {
                viewModel.clearCurrentSession()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("This releases the live dotAnky string and gives this session a blank page.")
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

}

private struct WriteTopActionBar: View {
    let isVisible: Bool
    let hasActiveDotAnky: Bool
    let canBeginNewPage: Bool
    let openMap: () -> Void
    let paste: () -> Void
    let devPaste: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack {
            HStack {
                if !hasActiveDotAnky {
                    Button(action: openMap) {
                        WriteChromeIcon(systemName: "chevron.left", isEnabled: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Map")
                }

                Spacer()

                HStack(spacing: 10) {
                    if hasActiveDotAnky && canBeginNewPage {
                        Button(action: clear) {
                            WriteChromeIcon(systemName: "doc.badge.plus", isEnabled: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Begin a new page")
                    }

                    if !hasActiveDotAnky {
                        DevPasteChromeIcon(
                            paste: paste,
                            devPaste: devPaste
                        )
                        .accessibilityLabel("Paste .anky artifact")
                    }
                }
            }
            Spacer()
        }
        .safeAreaPadding(.top, 8)
        .padding(.horizontal, 10)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeInOut(duration: 0.26), value: isVisible)
        .animation(.easeInOut(duration: 0.20), value: hasActiveDotAnky)
    }
}

private struct WriteChromeIcon: View {
    let systemName: String
    let isEnabled: Bool
    var isActive: Bool = false

    private var foregroundColor: Color {
        if !isEnabled {
            return Color.secondary.opacity(0.38)
        }
        return isActive ? Color.white.opacity(0.96) : Color.primary.opacity(0.74)
    }

    private var borderColor: Color {
        isActive ? Color.white.opacity(0.62) : Color.primary.opacity(0.10)
    }

    private var shadowColor: Color {
        isActive ? AnkyTheme.gold.opacity(0.42) : Color.black.opacity(0.08)
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 42, height: 42)
            .background(.thinMaterial, in: Circle())
            .background(Circle().fill(isActive ? AnkyTheme.gold.opacity(0.86) : Color.clear))
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: isActive ? 1.5 : 1)
            )
            .shadow(color: shadowColor, radius: isActive ? 16 : 10, y: 4)
            .opacity(isEnabled ? 1 : 0.62)
            .contentShape(Circle())
            .animation(.easeInOut(duration: 0.22), value: isActive)
    }
}

private struct DevPasteChromeIcon: View {
    let paste: () -> Void
    let devPaste: () -> Void

    var body: some View {
        WriteChromeIcon(systemName: "doc.on.clipboard", isEnabled: true)
            .gesture(
                LongPressGesture(minimumDuration: 5)
                    .exclusively(before: TapGesture())
                    .onEnded { value in
                        switch value {
                        case .first(true):
                            devPaste()
                        case .second:
                            paste()
                        default:
                            break
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
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
    private static let outerDiameter: CGFloat = 102
    private static let jewelDiameter: CGFloat = 80
    private static let mirrorDiameter: CGFloat = 56
    private static let silenceDiameter: CGFloat = 65

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
                        .frame(width: Self.outerDiameter + 10, height: Self.outerDiameter + 10)
                        .shadow(color: AnkyTheme.gold.opacity(0.36 + completePulse * 0.24), radius: 9 + completePulse * 5)
                        .shadow(color: Color.white.opacity(0.14 + completePulse * 0.14), radius: 4 + completePulse * 3)
                        .transition(.opacity)
                }

                Circle()
                    .fill(Color(red: 0.035, green: 0.024, blue: 0.016).opacity(0.94))
                    .frame(width: Self.outerDiameter, height: Self.outerDiameter)
                    .shadow(color: Color.black.opacity(0.72), radius: 8, y: 2)

                Circle()
                    .fill(PortalPalette.bronzeGradient)
                    .frame(width: Self.outerDiameter - 5, height: Self.outerDiameter - 5)

                Circle()
                    .fill(Color(red: 0.08, green: 0.055, blue: 0.035))
                    .frame(width: Self.outerDiameter - 17, height: Self.outerDiameter - 17)

                ZStack {
                    ForEach(colors.indices, id: \.self) { index in
                        let phase = (time * 1.8) + Double(index) * 0.72
                        let shimmer = (sin(phase) + 1) / 2
                        let progress = segmentProgress(index)
                        let isActive = progress > 0 && progress < 1

                        RingSegment(
                            index: index,
                            progress: 1,
                            color: colors[index].opacity(0.13 + shimmer * 0.05),
                            lineWidth: 15,
                            diameter: Self.jewelDiameter
                        )

                        if progress > 0 {
                            RingSegment(
                                index: index,
                                progress: progress,
                                color: colors[index].opacity((isActive ? 0.72 : 0.90) + shimmer * 0.10),
                                lineWidth: 15.4 + (isActive ? breath * 1.0 : 0),
                                diameter: Self.jewelDiameter
                            )
                            .shadow(color: colors[index].opacity((isActive ? 0.30 : 0.18) + shimmer * 0.18), radius: isActive ? 4.0 + shimmer * 2.4 : 2.4)
                        }
                    }
                }
                .scaleEffect(0.995 + breath * 0.010)

                ForEach(0..<8, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 0.16, green: 0.09, blue: 0.04).opacity(0.92))
                        .frame(width: 3, height: 18)
                        .offset(y: -Self.jewelDiameter / 2 + 3)
                        .rotationEffect(.degrees(Double(index) * 45 + 22.5))
                        .shadow(color: Color.black.opacity(0.34), radius: 1)
                }

                Circle()
                    .stroke(PortalPalette.bronzeGradient, lineWidth: 5)
                    .frame(width: Self.mirrorDiameter + 9, height: Self.mirrorDiameter + 9)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.16 + breath * 0.05),
                                Color.cyan.opacity(0.10),
                                Color.black.opacity(0.82),
                                Color.black.opacity(0.96)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.24),
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: Self.mirrorDiameter, height: Self.mirrorDiameter)
                    .overlay(
                        Circle()
                            .stroke(AnkyTheme.gold.opacity(0.30), lineWidth: 1.5)
                    )
                    .overlay(
                        Circle()
                            .trim(from: 0.56, to: 0.82)
                            .stroke(Color.white.opacity(0.24 + breath * 0.12), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-22))
                            .blur(radius: 0.8)
                    )

                PortalProgressCursor(
                    progress: ritualProgress,
                    diameter: Self.jewelDiameter,
                    isComplete: isRitualComplete,
                    breath: breath
                )

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.72 + breath * 0.18),
                                    AnkyTheme.gold.opacity(0.30 + breath * 0.18),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 1,
                                endRadius: 22
                            )
                        )
                        .frame(width: 44, height: 44)
                        .blur(radius: 2 + breath * 2)

                    Capsule()
                        .fill(Color.white.opacity(0.34 + breath * 0.20))
                        .frame(width: 21, height: 4)
                        .blur(radius: 1.4)
                        .offset(x: 10)
                }
                .offset(x: Self.jewelDiameter / 2 - 5)
                .blendMode(.plusLighter)
                .opacity(elapsedMs > 0 ? 1 : 0.54)

                if let lastCharacter {
                    Text(String(lastCharacter))
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundStyle(lastCharacterColor.opacity(0.94))
                        .shadow(color: lastCharacterColor.opacity(0.52), radius: 7)
                        .shadow(color: AnkyTheme.gold.opacity(0.22), radius: 10)
                        .id(pulseID)
                        .transition(.scale(scale: 0.74).combined(with: .opacity))
                        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: pulseID)
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

private struct RingSegment: View {
    let index: Int
    let progress: Double
    let color: Color
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
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
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
        layoutIfNeeded()
        guard !text.isEmpty else {
            return
        }

        let endRange = NSRange(location: (text as NSString).length, length: 0)
        scrollRangeToVisible(endRange)

        let bottomLimit = max(
            -adjustedContentInset.top,
            contentSize.height - bounds.height + adjustedContentInset.bottom
        )
        if contentOffset.y > bottomLimit {
            setContentOffset(CGPoint(x: contentOffset.x, y: bottomLimit), animated: false)
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
