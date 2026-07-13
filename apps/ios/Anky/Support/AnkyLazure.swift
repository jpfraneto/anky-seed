//
//  AnkyLazure.swift
//  Anky — a design system painted the way Steiner painted.
//
//  Lazure (Lasur) is wet-on-wet layering: color is never applied flat,
//  it is *breathed* onto the surface in translucent veils. Nothing has
//  a hard edge. Nothing is pure white or pure black. Every surface is
//  alive with slow movement of tone.
//
//  Four rules enforced by this file:
//    1. NO FLAT FILLS.   Every background is a wash (gradient), even buttons.
//    2. NO PURE VALUES.  White → tinted paper. Black → deep violet ink.
//    3. NO HARD SHADOWS. Shadows are colored (violet), soft, and low.
//    4. EVERYTHING BREATHES. Ambient motion cycles at 8 seconds — the
//       same 8s of silence that seals a writing session.
//
//  MeshGradient needs iOS 18; on iOS 16/17 the wall falls back to
//  layered radial washes whose centers drift on the same breath.
//

import SwiftUI
import UIKit

// MARK: - 1. Pigments (drawn from the poster)

/// Watercolor pigments, not "brand colors."
/// All defined in Display P3, all desaturated the way real pigment
/// sinks into wet paper.
extension Color {

    // The paper itself. Never use .white anywhere in the app.
    static let ankyPaper      = Color(.displayP3, red: 0.965, green: 0.937, blue: 0.894) // warm ivory
    static let ankyPaperDeep  = Color(.displayP3, red: 0.929, green: 0.882, blue: 0.835) // where washes pool

    // The ink. Never use .black anywhere in the app.
    static let ankyInk        = Color(.displayP3, red: 0.239, green: 0.216, blue: 0.310) // deep violet-slate
    static let ankyInkSoft    = Color(.displayP3, red: 0.396, green: 0.369, blue: 0.475) // secondary text

    // The writing ink — warm umber, sepia on parchment (phase-2 §7 sepia pass).
    static let ankyUmber      = Color(.displayP3, red: 0.310, green: 0.243, blue: 0.180)

    // Anky's own skin — the blue-slate of the character.
    static let ankySlate      = Color(.displayP3, red: 0.353, green: 0.427, blue: 0.514)

    // The curls and vest — muted violet.
    static let ankyViolet     = Color(.displayP3, red: 0.478, green: 0.392, blue: 0.541)

    // The warmth entering from above — apricot and the spiral sun.
    static let ankyApricot    = Color(.displayP3, red: 0.918, green: 0.741, blue: 0.573)
    static let ankyGold       = Color(.displayP3, red: 0.878, green: 0.694, blue: 0.427) // jewelry, accents
    static let ankyGoldLight  = Color(.displayP3, red: 0.965, green: 0.847, blue: 0.631) // the thread of light

    // The green that hides in the background washes.
    static let ankySage       = Color(.displayP3, red: 0.678, green: 0.714, blue: 0.604)

    // The rose that blushes at the edges.
    static let ankyRose       = Color(.displayP3, red: 0.851, green: 0.671, blue: 0.647)

    // The one warning pigment — madder, never firetruck red.
    static let ankyMadder     = Color(.displayP3, red: 0.702, green: 0.325, blue: 0.302)
}

// MARK: - 2. Breath (motion constants)

/// One breath = 8 seconds. All ambient motion in the app shares this
/// clock, so every surface inhales and exhales together.
enum AnkyBreath {
    static let cycle: Double = 8.0

    /// A smooth 0→1→0 phase driven by the shared 8s clock.
    static func phase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
        return 0.5 - 0.5 * cos(t * 2 * .pi)   // eased, no jolt at the loop point
    }
}

// MARK: - 3. The Wall (breathing wash background)

/// The foundational surface of every screen. On iOS 18 a MeshGradient
/// whose control points drift on the 8-second breath — Steiner's lazure
/// walls were painted so the color would seem to move as light changed;
/// here it actually does, but so slowly you feel it more than see it.
struct LazureWall: View {
    enum Mood {
        case dawn      // apricot & gold entering from above (default)
        case dusk      // violet-forward, for evening sessions
        case kingdom(Color) // tinted toward a kingdom pigment

        var pigments: (top: Color, mid: Color, low: Color) {
            switch self {
            case .dawn:           return (.ankyApricot, .ankyGoldLight, .ankyViolet)
            case .dusk:           return (.ankyViolet,  .ankyRose,      .ankySlate)
            case .kingdom(let c): return (c,            .ankyGoldLight, .ankyViolet)
            }
        }
    }

    var mood: Mood = .dawn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(mood: Mood = .dawn) { self.mood = mood }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let p = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)
            wash(phase: p)
                .background(Color.ankyPaper)      // pigment sits ON paper
                .overlay(PaperGrain())            // the tooth of the sheet
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func wash(phase p: Double) -> some View {
        let (top, mid, low) = mood.pigments
        if #available(iOS 18.0, *) {
            let drift = Float(0.04 * (p - 0.5) * 2)   // ±0.04 — felt, not seen
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5 + drift, 0.45 - drift], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    // Warmth always enters from above, like the sun
                    // spiral in the poster.
                    top.opacity(0.55),  mid.opacity(0.65),  top.opacity(0.45),
                    Color.ankySage.opacity(0.30), Color.ankyPaper, Color.ankyRose.opacity(0.30),
                    low.opacity(0.40),  Color.ankySlate.opacity(0.35), low.opacity(0.50)
                ]
            )
        } else {
            // iOS 16/17: three overlapping radial washes drifting on the
            // same breath. Softer than the mesh, same weather.
            let drift = 0.04 * (p - 0.5) * 2
            ZStack {
                Color.ankyPaper
                RadialGradient(
                    colors: [mid.opacity(0.65), top.opacity(0.35), .clear],
                    center: UnitPoint(x: 0.5 + drift, y: 0.0),
                    startRadius: 0, endRadius: 480
                )
                RadialGradient(
                    colors: [Color.ankySage.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.0, y: 0.55 - drift),
                    startRadius: 0, endRadius: 380
                )
                RadialGradient(
                    colors: [low.opacity(0.42), Color.ankySlate.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.5 - drift, y: 1.05),
                    startRadius: 0, endRadius: 520
                )
                RadialGradient(
                    colors: [Color.ankyRose.opacity(0.22), .clear],
                    center: UnitPoint(x: 1.0, y: 0.5 + drift),
                    startRadius: 0, endRadius: 340
                )
            }
        }
    }
}

// MARK: - 4. Paper grain

/// Real watercolor paper has tooth — tiny valleys where pigment pools.
/// A whisper of noise (≈3%) multiplied over every wash kills the
/// "digital gradient" smoothness that would betray the illusion.
struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            // Coarse deterministic speckle; cheap and stable.
            var rng = LazureSeededRandom(seed: 888)
            let cell: CGFloat = 3
            for x in stride(from: 0 as CGFloat, to: size.width, by: cell) {
                for y in stride(from: 0 as CGFloat, to: size.height, by: cell) {
                    let v = rng.next()   // 0...1
                    guard v > 0.72 else { continue }
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    context.fill(Path(rect),
                                 with: .color(Color.ankyInk.opacity(Double(v - 0.72) * 0.11)))
                }
            }
        }
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Deterministic RNG so the grain never shimmers between frames.
struct LazureSeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}

// MARK: - 5. Veils (cards & surfaces)

/// A card is not a box sitting ON the wall — it is one more translucent
/// veil of pigment laid over it. The wall's colors bleed through.
/// The edge is precise but subtle: a half-point line of the ink itself,
/// barely there, like the dry rim a wash leaves when it settles.
struct VeilCard<Content: View>: View {
    var tint: Color = .ankyPaper
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    init(tint: Color = .ankyPaper, padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        // Even the card fill is a wash, never flat.
                        LinearGradient(
                            colors: [tint.opacity(0.80), tint.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    // Edge defined by a darker tint of itself, not a border.
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
                    }
            }
            // Rule 3: shadows are violet air, not black holes.
            .shadow(color: Color.ankyViolet.opacity(0.14), radius: 18, y: 6)
    }
}

/// A hairline of ink between rows — the pencil rule under a line of
/// handwriting, not a wall between rooms.
struct LazureDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.ankyInk.opacity(0.08))
            .frame(height: 0.5)
    }
}

// MARK: - 6. The Thread (buttons)

/// The primary action is the golden thread Anky pulls from the sky.
/// It glows gently on the 8s breath while idle — an invitation,
/// not a demand.
struct ThreadButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    func makeBody(configuration: Configuration) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { context in
            let p = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)

            configuration.label
                .font(.ankyAction)
                .foregroundStyle(Color.ankyInk)
                .padding(.vertical, 15)
                .padding(.horizontal, 28)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.ankyGoldLight, .ankyGold],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
                        .shadow(color: Color.ankyGold.opacity(0.25 + 0.15 * p),
                                radius: 10 + 6 * p, y: 3)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

/// The parchment twin of ThreadButtonStyle: the same gold-thread capsule, but
/// filled with a pale paper→gold-light wash instead of solid gold. Onboarding
/// wears this from the first night screen through the paywall and gate setup,
/// so the primary action keeps one character the whole way and never "evolves"
/// into the brighter gold mid-flow.
struct PaperThreadButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold, design: .serif))
            .foregroundStyle(Color.ankyInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.ankyPaper.opacity(0.85), Color.ankyGoldLight.opacity(0.45)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [Color.ankyGoldLight, Color.ankyGold],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: Color.ankyGold.opacity(0.24), radius: 14, y: 4)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary actions are quieter washes of slate.
struct WashButtonStyle: ButtonStyle {
    init() {}
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ankyAction)
            .foregroundStyle(Color.ankyInk)
            .padding(.vertical, 15)
            .padding(.horizontal, 28)
            .background {
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.ankySlate.opacity(0.18), Color.ankyViolet.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Color.ankyInk.opacity(0.10), lineWidth: 0.5))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 7. Letterforms

/// Steiner's world is humanist: serifs for what is *said*, warmth for
/// what is *done*. New York (Apple's serif) for reflective text keeps
/// the app native while feeling hand-set.
extension Font {
    /// Screen titles — serif, light, generous.
    static let ankyTitle   = Font.system(.largeTitle, design: .serif).weight(.regular)
    /// Section headings.
    static let ankyHeading = Font.system(.title3, design: .serif).weight(.medium)
    /// The user's own writing & Anky's reflections — serif, readable.
    static let ankyProse   = Font.system(.body, design: .serif)
    /// UI chrome, labels, counts — default sans, never shouting.
    static let ankyLabel   = Font.system(.subheadline, design: .default).weight(.medium)
    /// Tiny captions under things.
    static let ankyCaption = Font.system(.caption, design: .default).weight(.regular)
    /// Buttons.
    static let ankyAction  = Font.system(.body, design: .serif).weight(.semibold)
}

// MARK: - 8. The Sun (spiral glyph)

/// The little sun from the poster — a ring of rays with a spiral heart.
/// Drawn, not typeset: no SF Symbol has a spiral heart.
struct AnkySunGlyph: View {
    var size: CGFloat = 28
    var color: Color = .ankyGold

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let r = min(canvasSize.width, canvasSize.height) / 2
            let stroke = max(1.1, r * 0.09)

            // Rays — twelve short strokes, hand-spaced.
            for i in 0..<12 {
                let angle = Double(i) / 12 * 2 * .pi
                var ray = Path()
                ray.move(to: CGPoint(
                    x: center.x + cos(angle) * r * 0.72,
                    y: center.y + sin(angle) * r * 0.72
                ))
                ray.addLine(to: CGPoint(
                    x: center.x + cos(angle) * r * 0.98,
                    y: center.y + sin(angle) * r * 0.98
                ))
                context.stroke(ray, with: .color(color),
                               style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }

            // Ring.
            let ring = Path(ellipseIn: CGRect(
                x: center.x - r * 0.52, y: center.y - r * 0.52,
                width: r * 1.04, height: r * 1.04
            ))
            context.stroke(ring, with: .color(color), lineWidth: stroke)

            // Spiral heart.
            var spiral = Path()
            let turns = 2.2
            let steps = 60
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let angle = t * turns * 2 * .pi
                let radius = r * 0.34 * t
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                if step == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
            }
            context.stroke(spiral, with: .color(color),
                           style: StrokeStyle(lineWidth: stroke * 0.9, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 8.5 The veiled feature (phase-3 §3)

/// One treatment for everything the free tier stands next to: the feature's
/// real UI rendered beneath a soft parchment mist, the small spiral sun (no
/// padlocks, no red, never pure black), one quiet line, and the whole
/// surface one tap from the paywall. It must read as *not yet* — the thing
/// is really there, breathing under the veil — never as *denied*.
struct VeiledFeature<Content: View>: View {
    /// Funnel tag for `veil_tapped {surface}` — "reflection", "ceremony",
    /// "journey".
    let surface: String
    let message: String
    let onTap: () -> Void
    let content: Content

    init(
        surface: String,
        message: String,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.message = message
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        Button {
            AnkyHaptics.light()
            AnkyFunnel.report(AnkyFunnel.veilTapped, origin: surface)
            onTap()
        } label: {
            ZStack {
                content
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // Parchment mist: a paper wash so the feature stays visible
                // but restful, with the breathing watercolor over it.
                Rectangle()
                    .fill(Color.ankyPaper.opacity(0.62))
                WatercolorVeilView(register: .pale)
                    .opacity(0.8)

                VStack(spacing: 12) {
                    AnkySunGlyph(size: 30, color: .ankyGold)
                    Text(AnkyLocalization.ui(message))
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Color.ankyInkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.ankyInk.opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(AnkyLocalization.ui(message)))
    }
}

/// The shape of a reflection that exists but is not yet seen: a serif title
/// stroke and a few quiet body lines. Rendered beneath the reflection veil —
/// real enough to be longed for, abstract enough to promise nothing false.
struct ReflectionGhost: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.ankyViolet.opacity(0.35))
                .frame(width: 172, height: 20)
                .padding(.bottom, 4)
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.ankyInk.opacity(0.18))
                    .frame(height: 11)
                    .frame(maxWidth: index == 3 ? 190 : .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.ankyPaper.opacity(0.5))
        }
    }
}

/// The QA lifeline under any failed-mirror state: one sentence asking for a
/// screenshot, with "here" opening a WhatsApp thread straight to the founder
/// (feedback 2026-07-08). Shared by the sealing gate and the reveal page so
/// the two error surfaces can't drift.
struct FounderContactLine: View {
    static let founderWhatsAppURL = URL(string: "https://wa.me/56946481174")!

    /// Defaults suit paper surfaces; dark surfaces (the reveal page) pass
    /// their own pigments.
    var textColor: Color = Color.ankyInkSoft
    var linkColor: Color = Color.ankyViolet

    var body: some View {
        Link(destination: Self.founderWhatsAppURL) {
            (
                Text(AnkyLocalization.ui("take a screenshot of this and send it to the founder"))
                    .foregroundColor(textColor)
                + Text(" ")
                + Text(AnkyLocalization.ui("here"))
                    .foregroundColor(linkColor)
                    .underline()
            )
            .font(.system(size: 13, weight: .medium, design: .serif))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Finger-tracked back-swipe for route-swap "pushes". The app navigates by
/// swapping route enums, so there is no NavigationStack pop to inherit — an
/// end-of-drag route swap reads as a teleport (feedback 2026-07-08). Here the
/// page follows the finger from the left edge over whatever the caller
/// renders beneath, then commits (slides fully off before the route swap) or
/// settles back, like a real navigation pop.
struct InteractiveBackSwipeContainer<Content: View>: View {
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragX: CGFloat = 0
    @State private var isEngaged = false
    @State private var isCommitting = false

    private static var edgeWidth: CGFloat { 44 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            content()
                .offset(x: dragX)
                .overlay(alignment: .leading) {
                    // The pop shadow along the page's leading edge.
                    LinearGradient(
                        colors: [Color.ankyInk.opacity(0.18), Color.ankyInk.opacity(0)],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                    .frame(width: 14)
                    .offset(x: dragX - 14)
                    .opacity(dragX > 0 ? 1 : 0)
                    .allowsHitTesting(false)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .onChanged { value in
                            guard !isCommitting, value.startLocation.x < Self.edgeWidth else {
                                return
                            }
                            if !isEngaged {
                                // Engage only once the drag is clearly
                                // horizontal so edge-adjacent scrolls stay
                                // scrolls.
                                guard value.translation.width > 12,
                                      abs(value.translation.width) > abs(value.translation.height) else {
                                    return
                                }
                                isEngaged = true
                            }
                            dragX = max(0, value.translation.width)
                        }
                        .onEnded { value in
                            guard isEngaged, !isCommitting else {
                                return
                            }
                            isEngaged = false
                            let commits = value.translation.width > width * 0.34
                                || value.predictedEndTranslation.width > width * 0.62
                            if commits {
                                isCommitting = true
                                withAnimation(.easeOut(duration: 0.20)) {
                                    dragX = width
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) {
                                    onBack()
                                    dragX = 0
                                    isCommitting = false
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                                    dragX = 0
                                }
                            }
                        }
                )
        }
    }
}

// MARK: - 9. Writing typefaces (mapping the stored choice to real fonts)

/// The five hands Anky can write in. Chosen for the lazure world:
/// humanist, bookish, nothing geometric or cold.
extension AnkyWritingFontChoice {
    var displayName: String {
        switch self {
        case .quill:      return "Quill"        // New York serif — the default hand
        case .georgia:    return "Georgia"      // rounder, old-friend serif
        case .round:      return "Round"        // soft rounded sans
        case .plain:      return "Plain"        // quiet system sans
        case .typewriter: return "Typewriter"   // American Typewriter
        }
    }

    /// UIFont for the UITextView writing surface.
    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .quill:
            let base = UIFont.systemFont(ofSize: size, weight: .regular)
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .georgia:
            return UIFont(name: "Georgia", size: size) ?? UIFont.systemFont(ofSize: size)
        case .round:
            let base = UIFont.systemFont(ofSize: size, weight: .regular)
            if let descriptor = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        case .plain:
            return UIFont.systemFont(ofSize: size, weight: .regular)
        case .typewriter:
            return UIFont(name: "AmericanTypewriter", size: size) ?? UIFont.systemFont(ofSize: size)
        }
    }

    /// SwiftUI Font for previews and reflective text.
    func font(size: CGFloat) -> Font {
        switch self {
        case .quill:      return .system(size: size, design: .serif)
        case .georgia:    return .custom("Georgia", size: size)
        case .round:      return .system(size: size, design: .rounded)
        case .plain:      return .system(size: size)
        case .typewriter: return .custom("AmericanTypewriter", size: size)
        }
    }
}
