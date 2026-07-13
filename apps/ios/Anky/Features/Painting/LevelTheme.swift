import SwiftUI

/// Palette-driven theming: each level's painting tints the whole app.
///
/// Derived from the package's 4-6 swatches (dark → light): a background wash,
/// a glow tint for the frame, and a button warmth. Falls back to the lazure
/// sepia register when no painting is installed. Never pure black.
struct LevelTheme: Equatable {
    let swatches: [Color]
    let backgroundWash: Color
    let glowTint: Color
    let buttonWarmth: Color

    static let fallback = LevelTheme(
        swatches: [],
        backgroundWash: .ankyPaperDeep,
        glowTint: .ankyGold,
        buttonWarmth: .ankyGoldLight
    )

    init(swatches: [Color], backgroundWash: Color, glowTint: Color, buttonWarmth: Color) {
        self.swatches = swatches
        self.backgroundWash = backgroundWash
        self.glowTint = glowTint
        self.buttonWarmth = buttonWarmth
    }

    init(palette: [String]) {
        let colors = palette.compactMap(Color.fromHexSwatch)
        guard colors.count >= 3 else {
            self = .fallback
            return
        }
        // Palette arrives sorted dark → light.
        swatches = colors
        // The wash leans on the midtone, lifted toward parchment so text
        // stays readable and the darkness stays warm.
        let mid = colors[colors.count / 2]
        backgroundWash = mid.opacity(0.35)
        // Glow comes from the brightest swatch — usually the painting's gold.
        glowTint = colors[colors.count - 1]
        buttonWarmth = colors[max(0, colors.count - 2)]
    }

    init(package: PaintingPackage?) {
        if let package {
            self.init(palette: package.palette)
        } else {
            self = .fallback
        }
    }

    /// The LazureWall mood carrying this level's pigment.
    var wallMood: LazureWall.Mood {
        swatches.isEmpty ? .dawn : .kingdom(glowTint)
    }
}

extension Color {
    /// Parses "#rrggbb" into a Display P3 color, matching the lazure system.
    static func fromHexSwatch(_ hex: String) -> Color? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let raw = UInt32(value, radix: 16) else { return nil }
        return Color(
            .displayP3,
            red: Double((raw >> 16) & 0xFF) / 255,
            green: Double((raw >> 8) & 0xFF) / 255,
            blue: Double(raw & 0xFF) / 255
        )
    }
}
