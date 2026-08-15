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
    /// Writing is free; the reflection is the paid act (spec paywall
    /// placement). When sending is not allowed, the tap raises the paywall
    /// instead of the offering traveling.
    var sendAllowed: Bool = true
    var onNeedsPaywall: () -> Void = {}
    /// The privacy seam (outwards pivot §4.1): fired the instant an allowed
    /// send begins — the writer's explicit outward gesture. The axis wires
    /// this to start the reflection upload; nothing has left the device
    /// before this closure runs.
    var onSendBegan: () -> Void = {}
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
                                awaitingSend: axis.offeringStands
                            )
                        }
                    }
                    .frame(width: Self.diameter, height: Self.diameter)
                    .scaleEffect(1.0 + 0.02 * breath + 0.06 * emptyPulse)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // The Anchor's absolute screen position never changes, ever — including
        // when a keyboard is up (spec §2, §3; verification Q3). Ignore the
        // keyboard safe-area inset so a rising keyboard never lifts the Anchor
        // from its eternal place at the base.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .allowsHitTesting(recordArmed || axis.phase == .landing || axis.phase == .entryOpen)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        // Direct completion for assistive users — the same tap, named.
        .accessibilityAction(named: Text("Send to Anky")) {
            if axis.offeringStands {
                sendOffering()
            } else if axis.anchorTapIsNavigational {
                axis.anchorTapped()
            }
        }
    }

    /// One tap drives everything (crossroads redesign, 2026-07-24 — the
    /// sustained-hold vigil is gone): on the strata or an opened day the tap
    /// summons the writing device; with a late offering armed it sends the
    /// day; with the camera up it starts and stops the take.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { _ in
                if recordArmed {
                    // The camera is up: the Anchor starts and stops the take.
                    AnkyHaptics.light()
                    onRecordToggle()
                } else if axis.offeringStands {
                    // A late offering stands (an unreflected day armed at its
                    // base): the tap sends it. No hold — no friction.
                    sendOffering()
                } else if axis.anchorTapIsNavigational {
                    // Landing or opened entry: the tap puts the writing page
                    // in front of the whole display.
                    AnkyHaptics.selection()
                    axis.anchorTapped()
                } else {
                    // Nothing to carry, or a stray press: a faint pulse. The
                    // Geshtu does not carry empty offerings.
                    pulseOnce()
                }
            }
    }

    /// The offering travels — or the gate rises. The outward gesture (the
    /// upload) begins only on an allowed send (outwards pivot §4.1).
    private func sendOffering() {
        AnkyHaptics.light()
        if sendAllowed {
            onSendBegan()
            axis.sendOffering()
        } else {
            onNeedsPaywall()
        }
    }

    private func pulseOnce() {
        AnkyHaptics.light()
        withAnimation(.easeOut(duration: 0.18)) { emptyPulse = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.18)) { emptyPulse = 0 }
    }

    private var accessibilityLabel: Text {
        if recordArmed {
            return Text("Anchor. Start or stop recording.")
        }
        switch axis.phase {
        case .landing:
            return Text("Anchor. Begin writing.")
        case .entryOpen:
            return axis.offeringStands
                ? Text("Anchor. Send this day to Anky.")
                : Text("Anchor. Close this day and return to the present.")
        default:             return Text("Anchor.")
        }
    }

    private var accessibilityHint: Text {
        axis.offeringStands
            ? Text("Tap to send.")
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
/// miniature, spiral engraved in beech (product asset, 2026-07-15). It glows
/// softly at the base and, at reflection, sits fully at rest (spec §2, §6).
/// The electric X-ray face and its spark anticipation went with the vigil
/// (simplicity pass, 2026-07-24); an armed offering breathes a warmer gold.
private struct AnchorMedallion: View {
    var breath: Double
    var atRest: Bool
    /// An offering stands (an armed late offering over an open day): the
    /// glow warms and widens — a quiet invitation to tap.
    var awaitingSend: Bool = false

    var body: some View {
        // The face defines the layout size; the glow sits behind it without
        // expanding the footprint, so the Anchor's touch target stays small.
        Image("GeshtuAnchor")
            .resizable()
            .scaledToFit()
            .shadow(color: Color.ankyViolet.opacity(0.20), radius: 5, y: 2)
            .background {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.ankyGoldLight.opacity(
                                    atRest ? 0.28
                                    : (awaitingSend ? 0.52 : 0.38) + 0.16 * breath
                                ),
                                .clear
                            ],
                            center: .center, startRadius: 4,
                            endRadius: awaitingSend ? 72 : 58
                        )
                    )
                    .frame(width: awaitingSend ? 160 : 132, height: awaitingSend ? 160 : 132)
                    .blur(radius: 7)
            }
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
