import SwiftUI

/// Phase-2 §2: the emergency door. Thirty seconds of pastel breath — Anky
/// breathing, watercolor veils swelling and settling, a thin gold hairline
/// filling. No numerals, no guilt. Completing it opens the rest of the day;
/// leaving cancels it with nothing owed and nothing said.
struct EmergencyBreathView: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

    static let breathSeconds: TimeInterval = 30

    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt: Date?
    @State private var progress: Double = 0

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

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Color.ankyInkSoft.opacity(0.35))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AnkyLocalization.ui("Cancel"))
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.leading, 12)
        }
        .task {
            // Date-anchored so a dropped frame never stretches the breath.
            let start = Date()
            startedAt = start
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                progress = min(1, elapsed / Self.breathSeconds)
                if elapsed >= Self.breathSeconds {
                    onComplete()
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        .onChange(of: scenePhase) { phase in
            // Interruption cancels — no partial credit.
            if phase != .active {
                onCancel()
            }
        }
    }
}
