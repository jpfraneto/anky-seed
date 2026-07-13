package inc.anky.android.ui.lazure

import androidx.compose.ui.graphics.Color

/**
 * The eight Ankyverse day colors — exact port of the iOS
 * `AnkyverseDayPalette`. Days 1-7 are the rainbow of kingdoms
 * (sRGB hex, exactly as the Swift `Color(red:green:blue:)` literals);
 * day 8 is the cream sabbath.
 */
object AnkyverseDayPalette {

    fun color(dayInRegion: Int): Color = when (normalized(dayInRegion)) {
        1 -> Color(0xFFE5484D)
        2 -> Color(0xFFF97316)
        3 -> Color(0xFFFACC15)
        4 -> Color(0xFF22C55E)
        5 -> Color(0xFF2563EB)
        6 -> Color(0xFF4F46E5)
        7 -> Color(0xFFA855F7)
        else -> Color(0xFFFFF7E0)
    }

    /**
     * The glyph color that sits on the day color: warm ink on the two
     * light days (3 and 8) — never pure black — paper elsewhere.
     */
    fun symbolColor(dayInRegion: Int): Color = when (normalized(dayInRegion)) {
        3, 8 -> LazurePigments.ankyInk.copy(alpha = 0.82f)
        else -> LazurePigments.ankyPaper
    }

    /** Wraps any day number onto 1..8, clamping non-positive input to day 1. */
    fun normalized(dayInRegion: Int): Int = ((maxOf(dayInRegion, 1) - 1) % 8) + 1
}
