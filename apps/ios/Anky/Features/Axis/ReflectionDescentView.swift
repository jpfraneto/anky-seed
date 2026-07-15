//
//  ReflectionDescentView.swift
//  Anky — the Axis Redesign (spec §6).
//
//  Anky's reflection descends: 4–6 short lines settling top-to-bottom onto the
//  lazure ground, the topmost line slightly more luminous. The writer's own
//  words, returned and warmed — finite, received, no reply. No input field, no
//  chat, no chrome, no share UI. The Anchor glows softly at the base, at rest.
//
//  Latency hiding (spec §12): the reflection request fires at the sentinel
//  (channel close), so the eight-second vigil covers most of the generation.
//  If it is not ready on arrival, the cooled gold spiral tracery lingers,
//  pulsing very slowly — no spinner, no "Anky is thinking" copy. The ear is
//  simply still listening.
//

import SwiftUI

// MARK: - Coordinator

/// Owns the reflection request for the pending session and fires it at the
/// sentinel so the vigil hides the latency. Discarded when the writer walks
/// away unsent, per the existing privacy posture.
@MainActor
final class AxisReflectionCoordinator: ObservableObject {
    @Published private(set) var viewModel: RevealViewModel?

    private var task: Task<Void, Never>?
    private var currentHash: String?

    /// Fire generation for a just-sealed session. Idempotent per hash, so the
    /// request started at channel-close keeps streaming through the vigil.
    func begin(for session: SavedAnky) {
        if currentHash == session.hash, viewModel != nil { return }
        cancelTask()
        let vm = RevealViewModel(artifact: session)
        vm.reflectionSurface = "axis"
        // Generation fires here, at the sentinel — before the writer has chosen
        // to send. Hold the result in memory only; it reaches the store only if
        // the vigil sends (addendum A3 / verification Q4). An unsent session's
        // reflection is never attached to its entry as if it had been received.
        vm.persistsReflection = false
        viewModel = vm
        currentHash = session.hash
        task = Task { await vm.askAnkyForSealedSession() }
    }

    /// The vigil completed: the offering was carried. Commit the held reflection
    /// to the store so the sent day owns it in the strata (addendum A3 / Q4).
    func commit() {
        viewModel?.persistPendingReflection()
    }

    /// The day settled unsent, or a new session began: drop the in-flight
    /// result without ever persisting it (unsent ≠ sent — Q4).
    func discard() {
        cancelTask()
        viewModel = nil
        currentHash = nil
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }
}

// MARK: - The descent → settle (one continuous scroll)

/// The reflection and the landing strata are one continuous scroll (spec §7).
/// The reflection sits at the top; scrolling past it melts it away (fading and
/// shrinking on the scroll) and reveals the strata beneath — where the day just
/// sent is already the newest layer. When the reflection has fully left, the
/// axis settles to the landing.
struct ReflectionSettleView: View {
    @ObservedObject var viewModel: RevealViewModel
    @ObservedObject var axis: AxisState

    @State private var entries: [SavedAnky] = []
    @State private var didSettle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let space = "reflSettle"

    var body: some View {
        GeometryReader { outer in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    reflectionBlock
                        .frame(height: outer.size.height)

                    StrataColumn(axis: axis, entries: entries)
                        .background(settleSentinel)
                }
            }
            .coordinateSpace(name: Self.space)
        }
        .onAppear { entries = LocalAnkyArchive().list() }
    }

    @ViewBuilder
    private var reflectionBlock: some View {
        let content = ReflectionLinesView(lines: lines, reduceMotion: reduceMotion)
        if #available(iOS 17.0, *) {
            content.scrollTransition(.interactive, axis: .vertical) { view, phase in
                // Melts away as it scrolls up: fades and shrinks toward the
                // strata (spec §7). Untouched while it rests at identity.
                view
                    .opacity(phase.isIdentity ? 1 : max(0, 1 + phase.value))
                    .scaleEffect(phase.isIdentity ? 1 : 0.86)
                    .blur(radius: phase.isIdentity ? 0 : 3)
            }
        } else {
            content
        }
    }

    /// Fires once when the strata's top has risen past the screen top — the
    /// reflection has fully melted; the day takes its place among the days.
    private var settleSentinel: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(Self.space)).minY
            Color.clear
                .onChange(of: minY) { y in
                    if y < 6, !didSettle {
                        didSettle = true
                        axis.settleToLanding()
                    }
                }
        }
    }

    /// The reflection as 4–6 short lines. Prefers the finished text; otherwise
    /// shows whatever has streamed in so far.
    private var lines: [String] {
        Self.lines(from: viewModel)
    }

    static func lines(from viewModel: RevealViewModel) -> [String] {
        let source = viewModel.reflection?.reflection ?? viewModel.streamingReflectionMarkdown
        return source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Strip any stray markdown the model might emit.
            .map { $0.replacingOccurrences(of: "#", with: "")
                     .replacingOccurrences(of: "*", with: "")
                     .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The pure descent layout — the gold spiral tracery at the crown and the
/// 4–6 lines settling top-to-bottom, topmost most luminous (spec §6).
struct ReflectionLinesView: View {
    let lines: [String]
    var reduceMotion: Bool = false

    var body: some View {
        ZStack {
            SpiralTracery(reduceMotion: reduceMotion, listening: lines.isEmpty)
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 96)
                .frame(maxHeight: .infinity, alignment: .top)

            if !lines.isEmpty {
                VStack(spacing: 22) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.fraunces(index == 0 ? 22 : 19,
                                             weight: index == 0 ? .regular : .light,
                                             italic: index != 0))
                            .foregroundStyle(Color.ankyInk.opacity(index == 0 ? 0.95 : 0.78))
                            .multilineTextAlignment(.center)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -8)),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .animation(.easeOut(duration: 0.6), value: lines.count)
    }
}

/// The gold spiral tracery at the crown of the descent — the cooled ear. It
/// pulses slowly while still listening, then settles once the words arrive.
private struct SpiralTracery: View {
    var reduceMotion: Bool
    var listening: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let breath = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)
            let glow = listening ? (0.28 + 0.30 * breath) : 0.22
            AnchorSpiral()
                .stroke(Color.ankyGold.opacity(glow),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .shadow(color: Color.ankyGoldLight.opacity(0.4 * glow), radius: 8)
        }
    }
}
