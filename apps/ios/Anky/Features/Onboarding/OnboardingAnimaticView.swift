import SwiftUI
import UIKit

/// Whether the ~21s first-launch animatic still owes its one showing.
///
/// Persisted in the KEYCHAIN, not UserDefaults, so a reinstall that restores
/// an existing writer's identity never replays the intro (pack constraint 5)
/// — while a DEBUG fresh-install reset clears it along with the identity,
/// keeping the newborn-eyes testing loop honest. Writers who completed the
/// legacy onboarding are grandfathered as done.
enum OnboardingAnimaticLedger {
    private static let account = "onboarding.animatic.done.v1"

    static func needsOnboarding() -> Bool {
        if UserDefaults.standard.bool(forKey: "anky.onboardingCompleted") {
            return false
        }
        return ((try? KeychainClient().data(for: account)) ?? nil) == nil
    }

    static func markDone() {
        try? KeychainClient().save(Data([1]), account: account)
    }

    static func reset() {
        try? KeychainClient().delete(account: account)
    }
}

/// The first-launch animatic (implementation pack, 2026-07-17): nine still
/// frames, crossfades and slow zooms, one hard cut, the carve reveal, then a
/// dissolve that reveals the LIVE name-entry screen already rendered beneath
/// — the video does not end, it becomes the app. Wordless, silent, skippable
/// from 3s, first launch only.
struct OnboardingAnimaticView: View {
    /// Called after the writer submits their name. The ledger is already
    /// stamped by then; the owner fades this view away into the world.
    let onFinished: () -> Void

    @StateObject private var presenter = NameEntryPresenter()
    @State private var timeline = AnimaticTimeline.load()
    @State private var frames = AnimaticFrameStore()
    @State private var startedBeats: Set<Int> = []
    @State private var carveFraction: CGFloat = 0
    @State private var animaticOpacity: Double = 1
    @State private var animaticDismantled = false
    @State private var showsSkip = false
    @State private var driver: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // (a) The real name screen, alive the whole time. Interaction
            // arrives with keyboard focus at the handoff; there is nothing
            // to touch before that.
            NameEntryView(presenter: presenter) { _ in
                OnboardingAnimaticLedger.markDone()
                onFinished()
            }

            // (b)+(c) The animatic layer. The lazure dissolve is simply this
            // layer's opacity going to 0, revealing the live screen below.
            if !animaticDismantled, let timeline {
                AnimaticStage(
                    timeline: timeline,
                    frames: frames,
                    startedBeats: startedBeats,
                    carveFraction: carveFraction
                )
                .opacity(animaticOpacity)
                .allowsHitTesting(false)
            }

            // (d) The quiet way out, from 3s (App Review is unforgiving
            // about forced intros).
            if showsSkip && !animaticDismantled {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            skip()
                        } label: {
                            Text(AnkyLocalization.ui("skip"))
                                .font(.fraunces(15, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .padding(18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 14)
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .onAppear(perform: start)
        .onDisappear { driver?.cancel() }
    }

    // MARK: - The driver (one t0; all events derive from it)

    private func start() {
        guard driver == nil else { return }
        guard let timeline, !reduceMotion else {
            // Reduce Motion (or a missing timeline resource, which must
            // never strand the user): no animatic — land on the finished
            // name screen with a simple fade.
            animaticDismantled = true
            animaticOpacity = 0
            withAnimation(.easeInOut(duration: 0.4)) {
                presenter.completeInstantly(questionLength: NameEntryView.question.count)
            }
            return
        }
        driver = Task { await run(timeline) }
    }

    private struct Event {
        let ms: Int
        let action: @MainActor () -> Void
    }

    private func run(_ timeline: AnimaticTimeline) async {
        var events: [Event] = []

        for beat in timeline.beats {
            events.append(Event(ms: beat.start_ms) {
                _ = startedBeats.insert(beat.n)
            })
        }
        for step in timeline.carve_reveal.steps {
            let ease = Double(timeline.carve_reveal.stroke_ease_ms) / 1000
            events.append(Event(ms: step.t_ms) {
                withAnimation(.easeOut(duration: ease)) {
                    carveFraction = step.reveal_to
                }
            })
        }
        events.append(Event(ms: timeline.skipAppearsAtMs) {
            withAnimation(.easeInOut(duration: 0.5)) { showsSkip = true }
        })

        let handoff = timeline.handoff
        events.append(Event(ms: handoff.lazure_dissolve_start_ms) {
            withAnimation(.linear(duration: Double(handoff.lazure_dissolve_duration_ms) / 1000)) {
                animaticOpacity = 0
            }
        })
        events.append(Event(ms: handoff.lazure_dissolve_start_ms + handoff.lazure_dissolve_duration_ms) {
            animaticDismantled = true
        })

        // The typed question: the cursor arrives 500ms early, then the
        // characters land in the protocol's halting rhythm — the delays are
        // data, used verbatim.
        events.append(Event(ms: handoff.typing_start_ms - 500) {
            presenter.showsCursor = true
        })
        let questionLength = NameEntryView.question.count
        var cursor = handoff.typing_start_ms
        for index in 0..<questionLength {
            let delays = handoff.per_char_delays_ms
            cursor += delays[min(index, delays.count - 1)]
            let typed = index + 1
            events.append(Event(ms: cursor) {
                presenter.typedCharacterCount = typed
            })
        }
        events.append(Event(ms: cursor + handoff.keyboard_rise_delay_after_typing_ms) {
            presenter.showsCursor = false
            presenter.wantsFieldFocus = true
        })

        let t0 = ContinuousClock.now
        for event in events.sorted(by: { $0.ms < $1.ms }) {
            try? await Task.sleep(until: t0 + .milliseconds(event.ms), clock: .continuous)
            guard !Task.isCancelled else { return }
            await event.action()
        }
    }

    /// Straight to the finished name screen in under half a second: question
    /// fully typed, keyboard rising.
    private func skip() {
        driver?.cancel()
        driver = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            animaticOpacity = 0
        }
        animaticDismantled = true
        presenter.completeInstantly(questionLength: NameEntryView.question.count)
    }
}
