//
//  ReflectionDescentView.swift
//  Anky — the Geshtu Redesign (spec §6).
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
final class GeshtuReflectionCoordinator: ObservableObject {
    @Published private(set) var viewModel: RevealViewModel?
    /// Fires when a reflection for a sent vigil actually reaches the store —
    /// the only moment the free vigil may be marked spent (a vigil whose
    /// reflection never arrives keeps the credit).
    var onPersisted: (() -> Void)?

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
        vm.onReflectionPersisted = { [weak self] in self?.onPersisted?() }
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

// MARK: - The reflection canvas (one massive vertical surface)

/// The reflection surface, reshaped (product decision, 2026-07-15): one
/// continuous canvas. The writing rests at the very top exactly where it was
/// written — same font, its last line on the same spot it held while the
/// keyboard was up — and Anky's response unrolls from the space where the
/// keyboard stood, downward. Below that, the strata: scrolling the day past
/// the top settles it among the days (spec §7's melt is kept). Where the
/// timer was, the record and share affordances now rest.
struct AxisReflectionCanvas: View {
    @ObservedObject var viewModel: RevealViewModel
    @ObservedObject var axis: GeshtuState
    /// The sealed writing — the words that never move.
    let writingText: String
    /// The global y of the keyboard's top edge during the session: the line
    /// the writing rests on and the response descends from.
    let keyboardTop: CGFloat
    /// Share a tapped paragraph of the writing as a "YOU"-signed card (the
    /// fixed top chrome handles the surface-level share and record).
    let onShare: (String) -> Void
    /// Share a tapped paragraph of Anky's reply as an "ANKY"-signed card.
    let onShareReflection: (String) -> Void

    @State private var entries: [SavedAnky] = []
    @State private var didSettle = false
    @State private var preferences = WritingPreferencesStore().load()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let space = "axisReflectionCanvas"
    private static let keyboardLineID = "axis.reflection.keyboardLine"

    var body: some View {
        GeometryReader { outer in
            let outerFrame = outer.frame(in: .global)
            // The keyboard line in this canvas's coordinates, clamped so a
            // stale reading can never pin the writing off-screen.
            let keyboardLineY = min(
                max(160, keyboardTop - outerFrame.minY),
                max(160, outer.size.height - 96)
            )
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // The writing, in the writer's own writing font,
                        // bottom-anchored to the keyboard line — the same
                        // resting place WriteView held it at (its text bottom
                        // inset was keyboard overlap + 24).
                        TappableOreText(
                            text: writingText,
                            font: writingFont,
                            ink: Color.ankyUmber.opacity(0.88),
                            lineSpacing: writingLineSpacing,
                            onShare: { onShare($0) },
                            // The fixed top chrome's share honors this choice.
                            onSelectionChange: { axis.selectedQuote = $0 }
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 80)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(1, keyboardLineY - 24),
                            alignment: .bottomLeading
                        )

                        Color.clear.frame(height: 1).id(Self.keyboardLineID)

                        // From the space where the keyboard stood, downward:
                        // a quiet gold seam, then Anky's response.
                        reflectionBlock
                            .padding(.top, 23)
                            .padding(.bottom, 64)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: max(1, outer.size.height - keyboardLineY),
                                alignment: .top
                            )

                        StrataColumn(axis: axis, entries: entries)
                            .background(settleSentinel)
                    }
                }
                .coordinateSpace(name: Self.space)
                .onAppear {
                    // The canvas's top block IS the newest day — the strata
                    // beneath it must begin with the previous one, or the
                    // writer meets their own words twice.
                    let currentHash = axis.pendingSession?.hash
                    entries = LocalAnkyArchive().list().filter { $0.hash != currentHash }
                    preferences = WritingPreferencesStore().load()
                    // Land with the writing exactly where it stood: park the
                    // keyboard-line marker at the keyboard's old top edge.
                    // (For writing short enough to fit above the line this is
                    // a no-op; for long writing it shows the tail, as the
                    // session did.)
                    let fraction = max(0.05, min(0.95, (keyboardLineY - 24) / max(1, outer.size.height)))
                    proxy.scrollTo(Self.keyboardLineID, anchor: UnitPoint(x: 0.5, y: fraction))
                }
            }
        }
    }

    // MARK: The writing's own clothes

    private var writingFont: Font {
        Font(preferences.fontChoice.uiFont(size: preferences.textSize.pointSize))
    }

    private var writingLineSpacing: CGFloat {
        preferences.textSize.pointSize * 0.42
    }

    // MARK: The response

    @ViewBuilder
    private var reflectionBlock: some View {
        // The raw markdown, honored — GlazeMarkdownText wears the accents
        // (violet headings, gold strong, slate emphasis); nothing is stripped
        // away anymore.
        let source = (viewModel.reflection?.reflection ?? viewModel.streamingReflectionMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 0) {
            // The seam between the two voices — same hairline as the strata.
            Capsule()
                .fill(Color.ankyGold.opacity(0.30))
                .frame(width: 46, height: 1.5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 30)

            if viewModel.reflection == nil, viewModel.errorMessage != nil {
                // The request failed: say so, in register. The spiral must
                // never pulse forever over a dead request (feedback 2026-07-18)
                // — an ear that lost the thread admits it and can be asked
                // again. Retry re-enters the same streaming path.
                Button {
                    Task { await viewModel.askAnkyForSealedSession() }
                } label: {
                    VStack(spacing: 10) {
                        Text(AnkyLocalization.ui("the reflection was lost on the way"))
                            .font(.fraunces(16, weight: .light, italic: true))
                            .foregroundStyle(Color.ankyInkSoft)
                        Text(AnkyLocalization.ui("tap to ask again"))
                            .font(.fraunces(13, weight: .light))
                            .foregroundStyle(Color.ankyInk.opacity(0.8))
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(AnkyLocalization.ui("tap to ask again")))
            } else if source.isEmpty {
                // Still listening: the cooled gold tracery, pulsing slowly —
                // no spinner, no "thinking" copy.
                SpiralTracery(reduceMotion: reduceMotion, listening: true)
                    .frame(width: 96, height: 96)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else {
                // Anky's reply, choosable like the writing above it: tap a
                // paragraph and the blob shares it as an ANKY-signed card.
                TappableGlazeText(
                    text: source,
                    onShare: { onShareReflection($0) },
                    onSelectionChange: {
                        axis.selectedQuote = $0
                        axis.selectedQuoteIsAnky = $0 != nil
                    }
                )
                .padding(.horizontal, 30)
                .animation(.easeOut(duration: 0.6), value: source)
            }
        }
    }

    // MARK: Settling

    /// Fires once when the strata's top has risen past the screen top — the
    /// day has scrolled home; it takes its place among the days.
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
                            // Glaze, applied identically to every line (addendum
                            // A4); the topmost stays slightly more luminous (§6).
                            .glazeVoice()
                            .opacity(index == 0 ? 1.0 : 0.82)
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
