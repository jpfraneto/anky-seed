import SwiftUI
import UIKit

struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var keyboardHeight: CGFloat = 0
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
                let visibleHeight = max(1, geometry.size.height - keyboardHeight)
                let center = CGPoint(x: geometry.size.width / 2, y: visibleHeight / 2)

                ForwardOnlyTextView(
                    text: viewModel.displayedText,
                    focusID: viewModel.keyboardFocusID,
                    shouldFocus: shouldFocus,
                    bottomInset: keyboardHeight + 92,
                    onCharacter: viewModel.accept,
                    onRejectedInput: viewModel.nudgeInvalidInput
                )
                .padding(24)
                .frame(width: geometry.size.width, height: geometry.size.height)

                RitualRingsView(
                    elapsedMs: viewModel.elapsedMs,
                    silenceElapsedMs: viewModel.silenceElapsedMs,
                    silenceRemainingMs: viewModel.silenceRemainingMs,
                    lastCharacter: viewModel.lastCharacter,
                    isRitualComplete: viewModel.hasReachedRitualMark
                )
                .position(center)
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
        .statusBarHidden(false)
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardHeight = keyboardOverlap(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
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

    private func keyboardOverlap(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }

        return max(0, UIScreen.main.bounds.maxY - frame.minY)
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

private struct RitualRingsView: View {
    let elapsedMs: Int64
    let silenceElapsedMs: Int64
    let silenceRemainingMs: Int64
    let lastCharacter: Character?
    let isRitualComplete: Bool

    private let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .indigo, .purple, .white
    ]

    private var ritualProgress: Double {
        min(1, Double(elapsedMs) / Double(AnkyDuration.completeRitualMs))
    }

    private var silenceProgress: Double {
        min(1, max(0, Double(silenceElapsedMs - 3000) / 5000))
    }

    private var keyOpacity: Double {
        min(1, max(0, Double(silenceRemainingMs) / Double(AnkyDuration.terminalSilenceMs)))
    }

    var body: some View {
        ZStack {
            if isRitualComplete {
                TimelineView(.animation) { timeline in
                    let pulse = (sin(timeline.date.timeIntervalSinceReferenceDate * 3.2) + 1) / 2
                    Circle()
                        .stroke(
                            AnkyTheme.gold.opacity(0.30 + pulse * 0.34),
                            style: StrokeStyle(lineWidth: 15, lineCap: .round)
                        )
                        .frame(width: 186, height: 186)
                        .shadow(color: AnkyTheme.gold.opacity(0.50 + pulse * 0.24), radius: 18 + pulse * 10)
                        .shadow(color: Color.white.opacity(0.18 + pulse * 0.14), radius: 6 + pulse * 5)
                }
                .transition(.opacity)
            }

            ForEach(colors.indices, id: \.self) { index in
                RingSegment(
                    index: index,
                    progress: 1,
                    color: colors[index].opacity(0.16),
                    lineWidth: 10
                )

                RingSegment(
                    index: index,
                    progress: ritualProgress,
                    color: colors[index],
                    lineWidth: 10
                )
            }

            Circle()
                .trim(from: 0, to: silenceProgress)
                .stroke(
                    Color.white.opacity(0.42),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .scaleEffect(x: -1, y: 1)
                .frame(width: 154, height: 154)
                .opacity(silenceElapsedMs >= 3000 ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: silenceElapsedMs >= 3000)
                .animation(.linear(duration: 0.04), value: silenceProgress)

            if let lastCharacter {
                Text(String(lastCharacter))
                    .font(.system(size: 58, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary.opacity(keyOpacity))
                    .animation(.easeOut(duration: 0.2), value: keyOpacity)
            } else {
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(sin(phase * 3.4) > 0 ? 0.72 : 0.24))
                        .frame(width: 3, height: 54)
                }
            }
        }
        .frame(width: 190, height: 190)
        .animation(.easeInOut(duration: 0.4), value: isRitualComplete)
        .allowsHitTesting(false)
    }
}

private struct RingSegment: View {
    let index: Int
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let start = Double(index) / 8
        let end = min(Double(index + 1) / 8, progress)
        Circle()
            .trim(from: start, to: max(start, end))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .frame(width: 186, height: 186)
    }
}

private struct ForwardOnlyTextView: UIViewRepresentable {
    let text: String
    let focusID: UUID
    let shouldFocus: Bool
    let bottomInset: CGFloat
    let onCharacter: (Character) -> Void
    let onRejectedInput: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = CenteredTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .title3)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UIColor.label.withAlphaComponent(0.33)
        textView.tintColor = .clear
        textView.textAlignment = .natural
        textView.keyboardDismissMode = .none
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 18, left: 0, bottom: bottomInset, right: 0)
        textView.contentInset.bottom = bottomInset
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
        textView.isScrollEnabled = true

        if shouldFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.textContainerInset.bottom = bottomInset
        uiView.contentInset.bottom = bottomInset
        uiView.verticalScrollIndicatorInsets.bottom = bottomInset

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
        uiView.scrollRangeToVisible(NSRange(location: (uiView.text as NSString).length, length: 0))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(focusID: focusID, onCharacter: onCharacter, onRejectedInput: onRejectedInput)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var focusID: UUID
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

private final class CenteredTextView: UITextView {}
