import SwiftUI

/// Phase-2 §2: the emergency door. Thirty seconds of pastel breath — Anky
/// breathing, watercolor veils swelling and settling, a thin gold hairline
/// filling. No numerals, no guilt. Completing it opens the rest of the day;
/// leaving cancels it with nothing owed and nothing said. A skip button
/// stands under the breath for the moments that can't wait.
struct EmergencyBreathView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    static let breathSeconds: TimeInterval = 30

    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt: Date?
    @State private var progress: Double = 0
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.ankyPaper.ignoresSafeArea()
            LazureWall(mood: .dawn).ignoresSafeArea()

            // The veil is the breath guide: it already swells and settles on
            // AnkyBreath's cycle.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = AnkyBreath.phase(at: timeline.date)
                let swell = 1.0 + 0.05 * sin(phase * 2 * .pi)

                ZStack {
                    WatercolorVeilView(register: .pale)
                        .scaleEffect(swell)
                        .ignoresSafeArea()

                    ZStack {
                        Circle()
                            .stroke(Color.ankyGold.opacity(0.16), lineWidth: 1)
                            .frame(width: 236, height: 236)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                Color.ankyGold.opacity(0.42),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 236, height: 236)

                        AnkySpriteView(sequence: .seated, size: 128)
                            .scaleEffect(1.0 + 0.02 * sin(phase * 2 * .pi))
                    }
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Button(action: cancel) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.35))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AnkyLocalization.ui("Cancel"))
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.leading, 12)

                VStack(spacing: 10) {
                    Text(AnkyLocalization.ui("Breathe with Anky"))
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.ankyInk)
                        .multilineTextAlignment(.center)

                    Text(AnkyLocalization.ui("Stay for thirty seconds of breath, and your apps open for the rest of the day."))
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 36)
                .padding(.top, 4)

                Spacer()

                Button(action: finish) {
                    Text(AnkyLocalization.ui("Skip the breath — open my apps now"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ankyInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 46)
                        .background(Color.ankyPaper.opacity(0.72), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                        .shadow(color: Color.ankyViolet.opacity(0.12), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 26)
            }
        }
        .task {
            // Date-anchored so a dropped frame never stretches the breath.
            let start = Date()
            startedAt = start
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                progress = min(1, elapsed / Self.breathSeconds)
                if elapsed >= Self.breathSeconds {
                    finish()
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        .onChange(of: scenePhase) { phase in
            // Interruption cancels — no partial progress.
            if phase != .active {
                cancel()
            }
        }
    }

    /// Skip and the timer land on the same door; it opens exactly once.
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onComplete()
    }

    private func cancel() {
        guard !didFinish else { return }
        didFinish = true
        onCancel()
    }
}
