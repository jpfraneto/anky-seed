import SwiftUI
import UIKit

struct WriteView: View {
    @StateObject private var viewModel: WriteViewModel
    @Environment(\.scenePhase) private var scenePhase
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
            ForwardOnlyTextView(
                text: viewModel.displayedText,
                focusID: viewModel.keyboardFocusID,
                shouldFocus: shouldFocus,
                onCharacter: viewModel.accept
            )
            .padding(24)

            RitualRingsView(
                elapsedMs: viewModel.elapsedMs,
                silenceElapsedMs: viewModel.silenceElapsedMs,
                silenceRemainingMs: viewModel.silenceRemainingMs,
                lastCharacter: viewModel.lastCharacter,
                isRitualComplete: viewModel.hasReachedRitualMark
            )

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(16)
                    .background(.background)
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

            if !viewModel.hasStarted {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.abandonIfEmpty()
                            onCloseToMap()
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Open Map")
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
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
    let onCharacter: (Character) -> Void

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(focusID: focusID, onCharacter: onCharacter)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var focusID: UUID
        private let onCharacter: (Character) -> Void

        init(focusID: UUID, onCharacter: @escaping (Character) -> Void) {
            self.focusID = focusID
            self.onCharacter = onCharacter
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
                return false
            }

            onCharacter(character)
            return false
        }
    }
}

private final class CenteredTextView: UITextView {}
