package inc.anky.android.ui.lazure

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.colorspace.ColorSpaces

/**
 * Palette-driven theming: each level's painting tints the whole app.
 *
 * Port of the iOS `LevelTheme`. Derived from a painting package's 4-6
 * swatches (sorted dark -> light): a background wash, a glow tint for the
 * frame, and a button warmth. Falls back to the lazure sepia register when
 * no painting is installed. Never pure black.
 *
 * Pure data + pure derivation: no painting-package type is imported here.
 * Callers hand over the package's `palette` hex strings via [fromPalette].
 */
@Immutable
data class LevelTheme(
    val swatches: List<Color>,
    val backgroundWash: Color,
    val glowTint: Color,
    val buttonWarmth: Color,
) {

    /** The [LazureWall] mood carrying this level's pigment. */
    val wallMood: LazureMood
        get() = if (swatches.isEmpty()) LazureMood.Dawn else LazureMood.Kingdom(glowTint)

    companion object {
        /** iOS `LevelTheme.fallback` — the lazure sepia register. */
        val Fallback = LevelTheme(
            swatches = emptyList(),
            backgroundWash = LazurePigments.ankyPaperDeep,
            glowTint = LazurePigments.ankyGold,
            buttonWarmth = LazurePigments.ankyGoldLight,
        )

        /**
         * Derives the theme from a painting's meta palette ("#rrggbb"
         * strings, sorted dark -> light). Mirrors the iOS init exactly:
         *  - fewer than 3 parseable swatches -> [Fallback];
         *  - the wash leans on the midtone at 0.35 alpha, lifted toward
         *    parchment so text stays readable and the darkness stays warm;
         *  - glow comes from the brightest swatch — usually the painting's
         *    gold;
         *  - button warmth is the second-brightest.
         */
        fun fromPalette(palette: List<String>): LevelTheme {
            val colors = palette.mapNotNull(::colorFromHexSwatch)
            if (colors.size < 3) return Fallback
            val mid = colors[colors.size / 2]
            return LevelTheme(
                swatches = colors,
                backgroundWash = mid.copy(alpha = 0.35f),
                glowTint = colors[colors.size - 1],
                buttonWarmth = colors[maxOf(0, colors.size - 2)],
            )
        }
    }
}

/**
 * Parses "#rrggbb" into a Display P3 color, matching the lazure system
 * (port of the iOS `Color.fromHexSwatch`). Returns null unless the string
 * is exactly a leading `#` and six hex digits (surrounding whitespace
 * tolerated, like the Swift version).
 */
fun colorFromHexSwatch(hex: String): Color? {
    val value = hex.trim()
    if (!value.startsWith("#")) return null
    val body = value.drop(1)
    if (body.length != 6) return null
    val raw = body.toLongOrNull(radix = 16) ?: return null
    return Color(
        red = ((raw shr 16) and 0xFF).toFloat() / 255f,
        green = ((raw shr 8) and 0xFF).toFloat() / 255f,
        blue = (raw and 0xFF).toFloat() / 255f,
        alpha = 1f,
        colorSpace = ColorSpaces.DisplayP3,
    )
}
