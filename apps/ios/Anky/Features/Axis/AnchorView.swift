//
//  AnchorView.swift
//  Anky — the Axis Redesign (spec §2).
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
    @ObservedObject var axis: AxisState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The medallion's center sits this far above the safe-area bottom. Keep
    /// it fixed across every phase (spec §2).
    static let bottomInset: CGFloat = 58
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
                    AnchorMedallion(breath: breath, atRest: axis.phase == .reflection)
                        .frame(width: Self.diameter, height: Self.diameter)
                        .scaleEffect(1.0 + 0.02 * breath + 0.06 * emptyPulse)
                }
            }
            .padding(.bottom, Self.bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Circle().size(width: 96, height: 96))
        .allowsHitTesting(axis.phase == .landing || axis.phase == .channelClosed)
        // Tap: enters writing from the landing surface; a soft pulse at a
        // closed channel; suspended elsewhere (spec §2).
        .onTapGesture {
            if axis.anchorTapEntersWriting {
                AnkyHaptics.selection()
                axis.anchorTapped()
            } else {
                pulseOnce()
            }
        }
        // Long press: the send vigil, when a session rests unsent. With nothing
        // to carry, at most a faint pulse that drains (spec §2).
        // NOTE (Phase 4): the real vigil replaces this with a continuous press
        // that drives `charge` 0→1 and drains on early release; for now the
        // long press simply begins the vigil phase.
        .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 40) {
            if axis.anchorSupportsVigil {
                axis.beginVigil()
            } else {
                pulseOnce()
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private func pulseOnce() {
        AnkyHaptics.light()
        withAnimation(.easeOut(duration: 0.18)) { emptyPulse = 1 }
        withAnimation(.easeIn(duration: 0.5).delay(0.18)) { emptyPulse = 0 }
    }

    private var accessibilityLabel: Text {
        switch axis.phase {
        case .landing:       return Text("Anchor. Begin writing.")
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

// MARK: - The medallion

/// The Anchor's face: a small stone disc with an engraved spiral — the ear of
/// the Geshtu in miniature. Warm gold on the lazure surfaces; it glows softly
/// at the base and, at reflection, sits fully at rest (spec §2, §6).
private struct AnchorMedallion: View {
    var breath: Double
    var atRest: Bool

    private let spiralSize: CGFloat = 26

    var body: some View {
        // The disc defines the layout size; the glow sits behind it without
        // expanding the footprint, so the Anchor's touch target stays small.
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.ankyGoldLight, Color.ankyGold, Color.ankyApricot.opacity(0.92)],
                    center: UnitPoint(x: 0.44, y: 0.40),
                    startRadius: 1, endRadius: 30
                )
            )
            // A carved rim — a hair of ink, then a warm inner bevel.
            .overlay(Circle().strokeBorder(Color.ankyUmber.opacity(0.30), lineWidth: 1))
            .overlay(
                Circle()
                    .strokeBorder(Color.ankyGoldLight.opacity(0.7), lineWidth: 0.5)
                    .padding(1.5)
            )
            // The engraved spiral — a dark valley under a light rim, centered.
            .overlay {
                ZStack {
                    AnchorSpiral()
                        .stroke(Color.ankyUmber.opacity(0.55),
                                style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                        .frame(width: spiralSize, height: spiralSize)
                    AnchorSpiral()
                        .stroke(Color.ankyGoldLight.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                        .frame(width: spiralSize, height: spiralSize)
                        .offset(y: -0.5)
                }
            }
            .shadow(color: Color.ankyViolet.opacity(0.20), radius: 5, y: 2)
            // The glow it rests in — warm air, breathing, never a hard halo.
            .background {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ankyGoldLight.opacity(atRest ? 0.28 : 0.38 + 0.16 * breath),
                                     .clear],
                            center: .center, startRadius: 4, endRadius: 58
                        )
                    )
                    .frame(width: 132, height: 132)
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
