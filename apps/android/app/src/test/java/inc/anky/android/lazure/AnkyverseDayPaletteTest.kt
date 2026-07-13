package inc.anky.android.lazure

import androidx.compose.ui.graphics.Color
import inc.anky.android.ui.lazure.AnkyverseDayPalette
import inc.anky.android.ui.lazure.LazurePigments
import org.junit.Assert.assertEquals
import org.junit.Test

class AnkyverseDayPaletteTest {

    @Test
    fun sevenKingdomColorsAndTheCreamSabbathMatchIos() {
        assertEquals(Color(0xFFE5484D), AnkyverseDayPalette.color(1))
        assertEquals(Color(0xFFF97316), AnkyverseDayPalette.color(2))
        assertEquals(Color(0xFFFACC15), AnkyverseDayPalette.color(3))
        assertEquals(Color(0xFF22C55E), AnkyverseDayPalette.color(4))
        assertEquals(Color(0xFF2563EB), AnkyverseDayPalette.color(5))
        assertEquals(Color(0xFF4F46E5), AnkyverseDayPalette.color(6))
        assertEquals(Color(0xFFA855F7), AnkyverseDayPalette.color(7))
        assertEquals(Color(0xFFFFF7E0), AnkyverseDayPalette.color(8))
    }

    @Test
    fun daysWrapEveryEight() {
        for (day in 1..8) {
            assertEquals(AnkyverseDayPalette.color(day), AnkyverseDayPalette.color(day + 8))
            assertEquals(AnkyverseDayPalette.color(day), AnkyverseDayPalette.color(day + 80))
        }
    }

    @Test
    fun nonPositiveDaysClampToDayOne() {
        assertEquals(AnkyverseDayPalette.color(1), AnkyverseDayPalette.color(0))
        assertEquals(AnkyverseDayPalette.color(1), AnkyverseDayPalette.color(-5))
        assertEquals(1, AnkyverseDayPalette.normalized(0))
    }

    @Test
    fun symbolInkIsWarmOnLightDaysAndPaperElsewhere() {
        // Never pure black — the ink is warm.
        assertEquals(LazurePigments.ankyInk.copy(alpha = 0.82f), AnkyverseDayPalette.symbolColor(3))
        assertEquals(LazurePigments.ankyInk.copy(alpha = 0.82f), AnkyverseDayPalette.symbolColor(8))
        assertEquals(LazurePigments.ankyPaper, AnkyverseDayPalette.symbolColor(1))
        assertEquals(LazurePigments.ankyPaper, AnkyverseDayPalette.symbolColor(7))
    }
}
