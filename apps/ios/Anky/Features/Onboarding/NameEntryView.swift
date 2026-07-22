import SwiftUI

/// Drives the name screen's animatic entrance from outside: how much of the
/// question has been typed, whether the pre-typing cursor blinks, and when
/// the real field takes focus. After onboarding the screen is simply shown
/// complete (all values at rest).
@MainActor
final class NameEntryPresenter: ObservableObject {
    @Published var typedCharacterCount = 0
    @Published var showsCursor = false
    @Published var wantsFieldFocus = false

    func completeInstantly(questionLength: Int) {
        typedCharacterCount = questionLength
        showsCursor = false
        wantsFieldFocus = true
    }
}

/// The shipped name-entry screen — the literal view the animatic dissolves
/// into (implementation pack constraint 1: the handoff is pixel-identical by
/// construction, because this exact view is alive beneath the animatic the
/// whole time). Lazure ground, the Fraunces question, one quiet field. The
/// keyboard that rises is the real one, summoned by focusing the real field.
struct NameEntryView: View {
    @ObservedObject var presenter: NameEntryPresenter
    let onSubmit: (String) -> Void

    @State private var name = ""
    @FocusState private var fieldFocused: Bool

    static var question: String { AnkyLocalization.ui("what should i call you?") }

    var body: some View {
        ZStack {
            LazureWall(mood: .dawn)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                HStack(spacing: 2) {
                    Text(String(Self.question.prefix(presenter.typedCharacterCount)))
                        .font(.fraunces(26, weight: .light))
                        .foregroundStyle(Color.ankyInk)
                    if presenter.showsCursor {
                        TypingCursor()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)

                // The field arrives with the keyboard, never before.
                VStack(spacing: 10) {
                    TextField(
                        text: $name,
                        prompt: Text("")
                    ) {
                        EmptyView()
                    }
                    .focused($fieldFocused)
                    .font(.fraunces(22, weight: .regular))
                    .foregroundStyle(Color.ankyInk)
                    .tint(Color.ankyUmber)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    Rectangle()
                        .fill(Color.ankyInk.opacity(0.14))
                        .frame(width: 180, height: 0.5)
                }
                .opacity(presenter.wantsFieldFocus ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: presenter.wantsFieldFocus)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 36)
        }
        // The keyboard must not shove the question upward mid-handoff: the
        // layout ignores it; question and field live in the upper half.
        .ignoresSafeArea(.keyboard)
        .onChange(of: presenter.wantsFieldFocus) { wants in
            if wants { fieldFocused = true }
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = WritingAnchorStore()
        store.save(
            writerName: trimmed.isEmpty ? nil : trimmed,
            anchorSentence: store.anchorSentence
        )
        onSubmit(trimmed)
    }
}

/// The blinking caret that precedes the typed question — 1060ms period, per
/// the timeline. The real field's caret takes over once the keyboard rises.
private struct TypingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.06)
            Rectangle()
                .fill(Color.ankyUmber.opacity(phase < 0.53 ? 0.85 : 0))
                .frame(width: 2, height: 28)
        }
    }
}
