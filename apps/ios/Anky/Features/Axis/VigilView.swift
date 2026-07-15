//
//  VigilView.swift
//  Anky — the Axis Redesign (spec §5).
//
//  The electric register: the Geshtu interior as X-ray. A luminous spine with
//  exactly seven stops rises from the Anchor to the spiral ear at the top. As
//  the charge climbs, the writing itself lifts from its resting lines,
//  compresses toward the spine, and travels upward — lowest words brightest and
//  legible, near the crown thinning into filaments of current drunk by the
//  spiral. The screen does not slide; the writing leaves.
//
//  A pure function of `charge` (0…1). No particle fireworks, no lens flares, no
//  screen shake — an X-ray of an offering, not a special effect.
//

import SwiftUI

struct VigilView: View {
    /// 0…1 from the VigilController.
    var charge: Double
    /// The session's writing — the words that travel.
    var text: String

    // The cold palette of the electric register (spec §10): cobalt and pale
    // cyan luminance only, no warm hues.
    private let cyan = Color(.displayP3, red: 0.55, green: 0.80, blue: 1.0)
    private let deepCyan = Color(.displayP3, red: 0.30, green: 0.55, blue: 0.95)

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let anchorY = geo.size.height - geo.safeAreaInsets.bottom - 86
            let spiralCenter = CGPoint(x: cx, y: 158)
            let spiralR: CGFloat = 48
            let spineTop = spiralCenter.y + spiralR - 4
            let spineBottom = anchorY - 6
            let spineH = max(1, spineBottom - spineTop)
            let chargeY = spineBottom - spineH * charge

            ZStack {
                woodGrain(size: geo.size)

                // The full spine, faint — the vessel at rest.
                spinePath(cx: cx, top: spineTop, bottom: spineBottom)
                    .stroke(cyan.opacity(0.16), lineWidth: 2)

                // The lit spine, from the Anchor up to the charge line.
                spinePath(cx: cx, top: chargeY, bottom: spineBottom)
                    .stroke(
                        LinearGradient(colors: [cyan, deepCyan.opacity(0.7)],
                                       startPoint: .bottom, endPoint: .top),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .shadow(color: cyan.opacity(0.7), radius: 8)
                    .shadow(color: deepCyan.opacity(0.5), radius: 16)

                // The seven stations.
                ForEach(1...7, id: \.self) { i in
                    let f = Double(i) / 8.0
                    let y = spineBottom - spineH * f
                    let lit = charge >= f - 0.001
                    Capsule()
                        .fill(cyan.opacity(lit ? 0.95 : 0.20))
                        .frame(width: lit ? 32 : 20, height: 3)
                        .shadow(color: cyan.opacity(lit ? 0.85 : 0), radius: lit ? 7 : 0)
                        .position(x: cx, y: y)
                        .animation(.easeOut(duration: 0.25), value: lit)
                }

                // The traveling words, ascending the spine.
                TravelingWords(
                    words: words,
                    charge: charge,
                    centerX: cx,
                    spineBottom: spineBottom,
                    spineHeight: spineH,
                    tint: cyan
                )

                // The spiral ear at the crown, opening downward — it brightens
                // as the offering nears, and drinks the last filaments.
                AnchorSpiral()
                    .stroke(cyan.opacity(0.30 + 0.65 * charge),
                            style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .frame(width: spiralR * 2, height: spiralR * 2)
                    .shadow(color: cyan.opacity(0.6 * charge), radius: 14)
                    .position(spiralCenter)
            }
            .ignoresSafeArea()
        }
    }

    private var words: [String] {
        text
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func spinePath(cx: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: cx, y: bottom))
            p.addLine(to: CGPoint(x: cx, y: top))
        }
    }

    /// Faint blue wood-grain density — the interior of the vessel, X-rayed
    /// (spec §1, §10). Deterministic so it never shimmers.
    private func woodGrain(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            var rng = LazureSeededRandom(seed: 424242)
            let cx = canvasSize.width / 2
            for _ in 0..<90 {
                let x = rng.next() * canvasSize.width
                let y = rng.next() * canvasSize.height
                let len = 20 + rng.next() * 90
                let curve = (x - cx) / canvasSize.width   // bow away from the spine
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: x, y: y + len),
                    control: CGPoint(x: x + curve * 26, y: y + len / 2)
                )
                context.stroke(path, with: .color(cyan.opacity(0.05)), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The writing compressed toward the spine and climbing. The lowest words are
/// brightest and legible; higher words thin toward filaments and are drunk by
/// the spiral near the crown (spec §5).
private struct TravelingWords: View {
    let words: [String]
    let charge: Double
    let centerX: CGFloat
    let spineBottom: CGFloat
    let spineHeight: CGFloat
    let tint: Color

    /// How many words to lift — the beginning of what was written, enough to
    /// read a phrase at the base.
    private var shown: [String] { Array(words.prefix(16)) }

    var body: some View {
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, word in
                let n = max(1, shown.count)
                // 0 at the base (legible) → 1 near the crown (a filament).
                let rung = Double(index) / Double(n)
                // Words start bunched near the base and rise as the charge does.
                let baseY = spineBottom - CGFloat(rung) * spineHeight * 0.62
                let travel = CGFloat(charge) * spineHeight * (0.34 + 0.5 * rung)
                let y = baseY - travel
                // Legible at the base; thinning and dimming as it climbs and as
                // it nears the crown at high charge.
                let climb = 1 - min(1, max(0, (spineBottom - y) / spineHeight))
                let size = 20 - 12 * rung
                let opacity = (1 - rung * 0.7) * (0.35 + 0.65 * climb)

                Text(word)
                    .font(.fraunces(max(7, size), weight: .light, italic: true))
                    .foregroundStyle(tint.opacity(opacity))
                    .shadow(color: tint.opacity(0.5 * opacity), radius: 3)
                    .position(x: centerX, y: y)
            }
        }
    }
}
