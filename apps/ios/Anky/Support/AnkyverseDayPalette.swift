import SwiftUI

enum AnkyverseDayPalette {
    private struct Pigment {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(.displayP3, red: red, green: green, blue: blue)
        }

        func blended(toward other: Pigment, by amount: Double) -> Pigment {
            let t = min(1, max(0, amount))
            return Pigment(
                red: red + (other.red - red) * t,
                green: green + (other.green - green) * t,
                blue: blue + (other.blue - blue) * t
            )
        }
    }

    /// The eight Ankyverse pigments in their canonical order. Keeping their
    /// components here lets the writing wall move continuously between days,
    /// rather than snapping once per minute.
    private static let pigments: [Pigment] = [
        Pigment(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255),
        Pigment(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255),
        Pigment(red: 0xFA / 255, green: 0xCC / 255, blue: 0x15 / 255),
        Pigment(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255),
        Pigment(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255),
        Pigment(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255),
        Pigment(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255),
        Pigment(red: 1, green: 0xF7 / 255, blue: 0xE0 / 255)
    ]

    static func color(for dayInRegion: Int) -> Color {
        pigments[normalized(dayInRegion) - 1].color
    }

    /// A continuous red → orange → yellow → green → blue → indigo → purple
    /// → warm-white passage. `progress` is clamped, so a completed ritual
    /// remains in the final light instead of cycling back to red.
    static func color(at progress: Double) -> Color {
        let clamped = min(1, max(0, progress))
        let position = clamped * Double(pigments.count - 1)
        let lowerIndex = min(Int(position), pigments.count - 1)
        let upperIndex = min(lowerIndex + 1, pigments.count - 1)
        return pigments[lowerIndex]
            .blended(toward: pigments[upperIndex], by: position - Double(lowerIndex))
            .color
    }

    static func symbolColor(for dayInRegion: Int) -> Color {
        switch normalized(dayInRegion) {
        case 3, 8: Color.ankyInk.opacity(0.82) // never pure black — the ink is warm
        default: .ankyPaper
        }
    }

    private static func normalized(_ dayInRegion: Int) -> Int {
        ((max(dayInRegion, 1) - 1) % 8) + 1
    }
}

/// The live page's time-based lazure. The hue advances continuously through
/// the Ankyverse while the usual eight-second breath moves pigment through
/// the wet paper. Its base is explicitly opaque so the system appearance can
/// never become part of the paint mixture.
struct AnkyverseWritingWall: View {
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let breath = reduceMotion ? 0.5 : AnkyBreath.phase(at: context.date)
            let pigment = AnkyverseDayPalette.color(at: progress)

            ZStack {
                Color.ankyPaper

                if #available(iOS 18.0, *) {
                    let drift = Float(0.04 * (breath - 0.5) * 2)
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                            [0.0, 0.5], [0.5 + drift, 0.5 - drift], [1.0, 0.5],
                            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                        ],
                        colors: [
                            pigment.opacity(0.72), pigment.opacity(0.52), Color.ankyPaper,
                            pigment.opacity(0.42), pigment.opacity(0.62), pigment.opacity(0.34),
                            Color.ankyPaperDeep.opacity(0.72), pigment.opacity(0.44), Color.ankyPaper
                        ]
                    )
                } else {
                    let drift = 0.05 * (breath - 0.5) * 2
                    ZStack {
                        LinearGradient(
                            colors: [pigment.opacity(0.62), Color.ankyPaper.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        RadialGradient(
                            colors: [pigment.opacity(0.38), .clear],
                            center: UnitPoint(x: 0.78 + drift, y: 0.22 - drift),
                            startRadius: 0,
                            endRadius: 440
                        )
                        RadialGradient(
                            colors: [Color.ankyPaperDeep.opacity(0.36), .clear],
                            center: UnitPoint(x: 0.14 - drift, y: 0.9 + drift),
                            startRadius: 0,
                            endRadius: 520
                        )
                    }
                }

                PaperGrain()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}
