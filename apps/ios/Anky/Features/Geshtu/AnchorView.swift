//
//  AnchorView.swift
//  Anky — the Geshtu Redesign (spec §2).
//
//  The Anchor is the app's only navigation primitive. It lives in the axis
//  world as a ZStack overlay above the entire hierarchy, and its absolute
//  screen position never changes, in any phase, ever — this is what builds
//  the muscle memory. A small circular medallion, horizontally centered,
//  ~86pt above the bottom edge: inside the thumb arc, above the home-indicator
//  gesture zone.
//
//  It idles with a very slow breathing on the shared 8s clock. Never bouncy,
//  never badged, never red-dotted.
//

import SwiftUI

struct AnchorView: View {
    @ObservedObject var axis: GeshtuState
    @ObservedObject var vigil: VigilController
    /// The one-time onboarding rehearsal (spec §9): the Anchor takes a single
    /// slow inhale up the first station and back down, under the hint.
    var rehearsalInhale: Bool = false
    /// Writing is free; the vigil is the paid act (spec paywall placement).
    /// When the hold is not allowed, the press raises the paywall instead of
    /// beginning the charge — never mid-charge.
    var vigilAllowed: Bool = true
    var onNeedsPaywall: () -> Void = {}
    /// The selfie camera is up (user decision, 2026-07-16): the Anchor IS the
    /// record button — it wears the classic red-circle face, a tap starts the
    /// take, the face becomes the stop square, a tap ends it. Navigation and
    /// the vigil are suspended until the camera is dismissed.
    var recordArmed: Bool = false
    /// A take is running (drives the circle→square face).
    var isRecordingTake: Bool = false
    var onRecordToggle: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The medallion's center sits this far above the safe-area bottom. Keep
    /// it fixed across every phase (spec §2). Lowered 50pt on 2026-07-16
    /// (user decision): the Anchor rests nearly on the world's base edge.
    static let bottomInset: CGFloat = 8
    static let diameter: CGFloat = 56

    /// A soft one-shot pulse when the Anchor is touched with nothing to carry
    /// (spec §2): it swells faintly and drains. No charge begins.
    @State private var emptyPulse: CGFloat = 0
    @State private var pressStart: Date?
    @State private var inhaleOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                // The filament: the hint of the base of the spine, rising from
                // the Anchor once the channel has closed (spec §4).
                if axis.showsFilament {
                    AnchorFilament(reduceMotion: reduceMotion)
                        .frame(width: 3, height: 150)
                        .offset(y: -Self.diameter + 8)
                        .transition(.opacity)
                }

                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
                    let breath = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)
                    Group {
                        if recordArmed {
                            // The camera is up: the Anchor wears the record
                            // button's face — everyone knows this button.
                            RecordMedallion(isRecording: isRecordingTake, breath: breath)
                        } else {
                            AnchorMedallion(
                                breath: breath,
                                atRest: axis.phase == .reflection,
                                electric: axis.isElectricRegister,
                                charge: vigil.charge,
                                awaitingVigil: axis.anchorSupportsVigil,
                                time: context.date.timeIntervalSinceReferenceDate
                            )
                        }
                    }
                    .frame(width: Self.diameter, height: Self.diameter)
                    .scaleEffect(1.0 + 0.02 * breath + 0.06 * emptyPulse)
                    .offset(y: inhaleOffset)
                }
                .animation(.easeInOut(duration: 0.3), value: recordArmed)
                // The hit target: a 108pt circle centered on the medallion —
                // generous around the 56pt disc, still inside the thumb arc.
                // It must be anchored HERE, on the medallion, not on the
                // full-screen container (a shape on the container sits at its
                // top-leading origin and the Anchor becomes untouchable).
                .contentShape(Circle().inset(by: (Self.diameter - 108) / 2))
                .gesture(pressGesture)
            }
            .padding(.bottom, Self.bottomInset)
        }
        .onChange(of: rehearsalInhale) { on in
            guard on, !reduceMotion else { return }
            // A single slow breath up the first station and back — shown once.
            withAnimation(.easeInOut(duration: 1.5)) { inhaleOffset = -34 }
            withAnimation(.easeInOut(duration: 1.5).delay(1.6)) { inhaleOffset = 0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // The Anchor's absolute screen position never changes, ever — including
        // when a keyboard is up (spec §2, §3; verification Q3). Ignore the
        // keyboard safe-area inset so a rising keyboard never lifts the Anchor
        // from its eternal place at the base.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .allowsHitTesting(recordArmed || axis.phase == .landing || axis.phase == .channelClosed || axis.phase == .vigil || axis.phase == .entryOpen)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        // Direct completion for assistive users — the offering without the hold.
        .accessibilityAction(named: Text("Send to Anky")) {
            if axis.anchorSupportsVigil {
                if vigilAllowed {
                    axis.beginVigil()
                    axis.vigilCompleted()
                } else {
                    onNeedsPaywall()
                }
            } else if axis.anchorTapIsNavigational {
                axis.anchorTapped()
            }
        }
    }

    /// One continuous press drives everything (spec §2, §5): a quick tap
    /// enters writing from the landing surface or soft-pulses at a closed
    /// channel; a sustained hold at a closed channel is the send vigil,
    /// arming, charging, and completing — or draining on early release.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStart == nil else { return }
                pressStart = Date()
                guard !recordArmed else { return }
                if axis.anchorSupportsVigil {
                    if vigilAllowed {
                        configureVigil()
                        vigil.press(duration: effectiveVigilDuration)
                    } else {
                        // The paid act: the quiet lazure paywall rises
                        // instead of the charge beginning.
                        AnkyHaptics.light()
                        onNeedsPaywall()
                    }
                }
            }
            .onEnded { _ in
                pressStart = nil
                if recordArmed {
                    // The camera is up: the Anchor starts and stops the take.
                    AnkyHaptics.light()
                    onRecordToggle()
                } else if axis.phase == .vigil || vigil.stage != .idle {
                    vigil.lift()
                } else if axis.anchorTapIsNavigational {
                    // Landing or opened entry: resolve tap by scroll position
                    // — enter writing, surface to now, or close-then-surface
                    // (addendum A1). Held or quick, the release navigates.
                    AnkyHaptics.selection()
                    axis.anchorTapped()
                } else {
                    // channelClosed with nothing to carry, or a stray press:
                    // a faint pulse. The Geshtu does not carry empty offerings.
                    pulseOnce()
                }
            }
    }

    private func pulseOnce() {
        AnkyHaptics.light()
        withAnimation(.easeOut(duration: 0.18)) { emptyPulse = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.18)) { emptyPulse = 0 }
    }

    /// The ritual is attention, not endurance (spec §5): when assistive
    /// settings are active, the required hold is shortened. VoiceOver/Switch
    /// Control users also get a direct completion action (below).
    private var effectiveVigilDuration: TimeInterval {
        let base = axis.vigilDuration
        if reduceMotion || UIAccessibility.isSwitchControlRunning || UIAccessibility.isVoiceOverRunning {
            return max(GeshtuState.vigilFloorSeconds, min(base, 3))
        }
        return base
    }

    private func configureVigil() {
        vigil.onActivate = { axis.beginVigil() }
        vigil.onComplete = { axis.vigilCompleted() }
        vigil.onDrain = { axis.vigilDrained() }
        vigil.onTap = { AnkyHaptics.light() }
    }

    private var accessibilityLabel: Text {
        if recordArmed {
            return Text("Anchor. Start or stop recording.")
        }
        switch axis.phase {
        case .landing:
            return axis.landingAtTop
                ? Text("Anchor. Begin writing.")
                : Text("Anchor. Return to the present.")
        case .entryOpen:
            return axis.anchorSupportsVigil
                ? Text("Anchor. Hold to send this day to Anky.")
                : Text("Anchor. Close this day and return to the present.")
        case .channelClosed: return Text("Anchor. Hold to send your writing to Anky.")
        default:             return Text("Anchor.")
        }
    }

    private var accessibilityHint: Text {
        axis.anchorSupportsVigil
            ? Text("Press and hold to send.")
            : Text("")
    }
}

// MARK: - The record face

/// The Anchor's face while the camera is up: the universal record button —
/// paper ring, red circle to start, red square to stop (user decision,
/// 2026-07-16). The wooden ear returns when the camera is dismissed.
private struct RecordMedallion: View {
    var isRecording: Bool
    var breath: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ankyPaper.opacity(0.92))
            Circle()
                .strokeBorder(Color.ankyInk.opacity(0.30), lineWidth: 3)
            RoundedRectangle(cornerRadius: isRecording ? 5 : 20, style: .continuous)
                .fill(Color.ankyMadder)
                .frame(
                    width: isRecording ? 22 : 40,
                    height: isRecording ? 22 : 40
                )
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .shadow(color: Color.ankyMadder.opacity(isRecording ? 0.35 + 0.25 * breath : 0.30), radius: 9, y: 2)
    }
}

// MARK: - The medallion

/// The Anchor's face: the carved wooden medallion — the ear of the Geshtu in
/// miniature, spiral engraved in beech (product asset, 2026-07-15). In the
/// electric register it becomes the X-ray of itself, drawn in cyan. It glows
/// softly at the base and, at reflection, sits fully at rest (spec §2, §6).
private struct AnchorMedallion: View {
    var breath: Double
    var atRest: Bool
    var electric: Bool = false
    var charge: Double = 0
    /// A closed channel with an offering to carry (spec §4): the medallion
    /// anticipates the vigil — faint X-ray sparks of the electric register
    /// flicker off its rim, the same cyan current that fills the screen once
    /// the hold begins.
    var awaitingVigil: Bool = false
    /// Wall-clock seconds driving the spark flicker; frozen (a steady faint
    /// spark) when the owning TimelineView pauses for reduce-motion.
    var time: TimeInterval = 0

    private let spiralSize: CGFloat = 26
    private var cyan: Color { Color(.displayP3, red: 0.55, green: 0.80, blue: 1.0) }

    var body: some View {
        // The face defines the layout size; the glow and sparks sit behind and
        // over it without expanding the footprint, so the Anchor's touch
        // target stays small.
        face
            .shadow(color: Color.ankyViolet.opacity(0.20), radius: 5, y: 2)
            // The glow it rests in — warm air, breathing; in the electric
            // register it cools to cyan and brightens as the offering climbs.
            .background {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [electric
                                            ? cyan.opacity(0.35 + 0.5 * charge)
                                            : Color.ankyGoldLight.opacity(atRest ? 0.28 : 0.38 + 0.16 * breath),
                                         .clear],
                                center: .center, startRadius: 4, endRadius: 58
                            )
                        )
                        .frame(width: 132, height: 132)
                        .blur(radius: 7)
                    if awaitingVigil && !electric {
                        // The invitation (user decision, 2026-07-17, made
                        // LOUDER after it read as absent on device): the
                        // electric register gathers visibly under the wood —
                        // a breathing cyan corona wider than the warm glow,
                        // unmistakably asking for the hold.
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [cyan.opacity(0.45 + 0.30 * breath), .clear],
                                    center: .center, startRadius: 8, endRadius: 76
                                )
                            )
                            .frame(width: 168, height: 168)
                            .blur(radius: 8)
                    }
                }
            }
            .overlay {
                if awaitingVigil && !electric {
                    AnchorSparks(time: time, tint: cyan)
                        .frame(width: 120, height: 120)
                        .transition(.opacity)
                }
            }
    }

    @ViewBuilder
    private var face: some View {
        if electric {
            // The X-ray of the medallion: cool cyan disc, engraved spiral as
            // current.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cyan.opacity(0.9), cyan.opacity(0.5),
                                 Color(.displayP3, red: 0.08, green: 0.12, blue: 0.24)],
                        center: UnitPoint(x: 0.44, y: 0.40),
                        startRadius: 1, endRadius: 30)
                )
                .overlay(Circle().strokeBorder(Color.black.opacity(0.30), lineWidth: 1))
                .overlay(
                    Circle()
                        .strokeBorder(cyan.opacity(0.7), lineWidth: 0.5)
                        .padding(1.5)
                )
                .overlay {
                    ZStack {
                        AnchorSpiral()
                            .stroke(Color.black.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                            .frame(width: spiralSize, height: spiralSize)
                        AnchorSpiral()
                            .stroke(cyan.opacity(0.9),
                                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                            .frame(width: spiralSize, height: spiralSize)
                            .offset(y: -0.5)
                    }
                }
        } else {
            // The wooden medallion itself.
            Image("GeshtuAnchor")
                .resizable()
                .scaledToFit()
        }
    }
}

/// The anticipation of the vigil: short cyan filaments sparking off the
/// medallion's rim while an offering waits to be carried. Each spark has a
/// fixed, seeded place and its own slow flicker cycle — an intermittent
/// crackle of the current to come, never a particle firework (spec §10).
private struct AnchorSparks: View {
    var time: TimeInterval
    var tint: Color

    var body: some View {
        Canvas { context, size in
            context.addFilter(.shadow(color: tint.opacity(0.85), radius: 4))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var rng = LazureSeededRandom(seed: 616)
            for _ in 0..<13 {
                let angle = rng.next() * 2 * .pi
                let speed = 0.9 + rng.next() * 1.4
                let phase = rng.next() * 2 * .pi
                let root = 30.0 + rng.next() * 6
                let reach = 9.0 + rng.next() * 10
                // Bright only near the crest of its own cycle, dark otherwise
                // — so at any moment four or five sparks live, not all
                // thirteen.
                let flicker = max(0, sin(time * speed + phase) - 0.45) / 0.55
                guard flicker > 0.02 else { continue }
                let dir = CGPoint(x: cos(angle), y: sin(angle))
                var path = Path()
                path.move(to: CGPoint(x: center.x + dir.x * root,
                                      y: center.y + dir.y * root))
                path.addLine(to: CGPoint(x: center.x + dir.x * (root + reach * flicker),
                                         y: center.y + dir.y * (root + reach * flicker)))
                context.stroke(
                    path,
                    with: .color(tint.opacity(min(1, 0.25 + 0.75 * flicker))),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// The spiral heart, opening downward like the Geshtu's ear (spec §1). Drawn,
/// not typeset — a sibling of AnkySunGlyph's spiral, sized for the medallion.
struct AnchorSpiral: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxR = min(rect.width, rect.height) / 2
        let turns = 2.4
        let steps = 80
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = t * turns * 2 * .pi
            let radius = maxR * t
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The filament rising from the Anchor at a closed channel — the base of the
/// luminous spine, hinted (spec §4). A thin gold thread, brightest at its root.
private struct AnchorFilament: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let breath = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)
            LinearGradient(
                colors: [.clear, Color.ankyGoldLight.opacity(0.55 + 0.25 * breath)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2)
            .frame(maxWidth: .infinity)
            .blur(radius: 0.6)
        }
    }
}
