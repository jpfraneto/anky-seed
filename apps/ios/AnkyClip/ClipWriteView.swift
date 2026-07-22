import StoreKit
import SwiftUI
import UIKit

/// The clip's only screen: the writing surface, the sentinel's presence, and
/// nothing else. No character, no branding lockup, no second screen. When the
/// sentinel fires the surface freezes, the words stay, and the system App
/// Store overlay offers the full app — where this session will be waiting.
struct ClipWriteView: View {
    @ObservedObject var session: ClipSessionController
    @State private var showsStoreOverlay = false

    private var silenceRemaining: Double {
        Double(session.silenceRemainingMs) / Double(session.terminalSilenceMs)
    }

    var body: some View {
        ZStack {
            LazureWall()
                .ignoresSafeArea()

            switch session.phase {
            case .writing:
                writingSurface
            case .sealed:
                sealedSurface
            }
        }
        .onChange(of: session.phase) { phase in
            if phase == .sealed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showsStoreOverlay = true
                }
            }
        }
        .appStoreOverlay(isPresented: $showsStoreOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    private var writingSurface: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AnkyDuration.clock(session.elapsedMs))
                    .font(.fraunces(15, weight: .semibold))
                    .foregroundStyle(Color.ankyInk.opacity(0.45))
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            SilenceLifeBar(remaining: session.hasStarted ? silenceRemaining : 1)
                .frame(height: 2)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            ZStack(alignment: .topLeading) {
                ClipForwardOnlyTextView(
                    text: session.reconstructedText,
                    silenceProgress: session.silenceProgress,
                    onAppend: { session.accept($0) }
                )

                if !session.hasStarted {
                    Text(AnkyLocalization.ui("Write. Don't stop."))
                        .font(.fraunces(22, weight: .regular))
                        .foregroundStyle(Color.ankyInk.opacity(0.3))
                        .padding(.top, 24)
                        .padding(.leading, 24)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    private var sealedSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AnkyLocalization.ui("That was you, unfiltered."))
                .font(.fraunces(17, weight: .semibold))
                .foregroundStyle(Color.ankyUmber)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            ScrollView {
                Text(session.reconstructedText)
                    .font(.fraunces(20, weight: .regular))
                    .lineSpacing(8)
                    .foregroundStyle(Color.ankyInk.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        .transition(.opacity)
    }
}

/// The clip's forward-only input: appends land natively at the end of the
/// page; deletions, edits inside the text, and newlines are rejected — the
/// same filtering the app applies with backspace disallowed. Accepted text is
/// timed by `ClipSessionController` through the shared engine.
private struct ClipForwardOnlyTextView: UIViewRepresentable {
    let text: String
    let silenceProgress: Double
    let onAppend: (String) -> Void

    private static var writingFont: UIFont {
        let preferences = WritingPreferences.ritualDefault
        return preferences.fontChoice.uiFont(size: preferences.textSize.pointSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onAppend: onAppend)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = Self.writingFont
        textView.textColor = WritingRhythmColor.uiColor(progress: 0, alpha: 0.96)
        textView.tintColor = UIColor(Color.ankyUmber)
        textView.keyboardAppearance = .light
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 120, right: 24)
        textView.showsVerticalScrollIndicator = false
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        applyGlyphColors(to: uiView)
    }

    /// The sentinel's visual treatment, character-free: the latest glyph
    /// drifts ink→madder on the app's exact timing curve as silence runs.
    private func applyGlyphColors(to textView: UITextView) {
        let length = (textView.text as NSString).length
        guard length > 0 else {
            return
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.addAttribute(
            .foregroundColor,
            value: WritingRhythmColor.uiColor(progress: 0, alpha: 0.96),
            range: NSRange(location: 0, length: length)
        )
        let lastGlyphRange = (textView.text as NSString).rangeOfComposedCharacterSequence(at: length - 1)
        storage.addAttribute(
            .foregroundColor,
            value: WritingRhythmColor.uiColor(progress: silenceProgress, alpha: 0.96),
            range: lastGlyphRange
        )
        storage.addAttribute(.font, value: Self.writingFont, range: NSRange(location: 0, length: length))
        storage.endEditing()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let onAppend: (String) -> Void

        init(onAppend: @escaping (String) -> Void) {
            self.onAppend = onAppend
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let currentLength = (textView.text as NSString).length
            guard range.length == 0,
                  range.location == currentLength,
                  !text.isEmpty,
                  !text.contains("\n"), !text.contains("\r") else {
                return false
            }
            onAppend(text)
            return true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let end = (textView.text as NSString).length
            if textView.selectedRange.location != end || textView.selectedRange.length != 0 {
                textView.selectedRange = NSRange(location: end, length: 0)
            }
        }
    }
}
