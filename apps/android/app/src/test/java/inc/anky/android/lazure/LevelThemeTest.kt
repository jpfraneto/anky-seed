package inc.anky.android.lazure

import androidx.compose.ui.graphics.colorspace.ColorSpaces
import inc.anky.android.ui.lazure.LazureMood
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LevelTheme
import inc.anky.android.ui.lazure.colorFromHexSwatch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LevelThemeTest {

    @Test
    fun hexSwatchParsesIntoDisplayP3() {
        val color = colorFromHexSwatch("#8040C0")
        checkNotNull(color)
        assertEquals(ColorSpaces.DisplayP3, color.colorSpace)
        assertEquals(0x80.toFloat() / 255f, color.red, 0.001f)
        assertEquals(0x40.toFloat() / 255f, color.green, 0.001f)
        assertEquals(0xC0.toFloat() / 255f, color.blue, 0.001f)
        assertEquals(1f, color.alpha, 0.001f)
    }

    @Test
    fun hexSwatchToleratesWhitespaceAndCase() {
        assertEquals(colorFromHexSwatch("#aabbcc"), colorFromHexSwatch("  #AABBCC\n"))
    }

    @Test
    fun hexSwatchRejectsMalformedInput() {
        assertNull(colorFromHexSwatch("aabbcc")) // missing '#', like the Swift guard
        assertNull(colorFromHexSwatch("#abc")) // short form unsupported
        assertNull(colorFromHexSwatch("#aabbccdd")) // no alpha channel
        assertNull(colorFromHexSwatch("#zzzzzz")) // not hex
        assertNull(colorFromHexSwatch(""))
    }

    @Test
    fun fewerThanThreeSwatchesFallsBackToTheSepiaRegister() {
        assertEquals(LevelTheme.Fallback, LevelTheme.fromPalette(emptyList()))
        assertEquals(LevelTheme.Fallback, LevelTheme.fromPalette(listOf("#111111", "#eeeeee")))
        // Unparseable entries do not count toward the minimum.
        assertEquals(
            LevelTheme.Fallback,
            LevelTheme.fromPalette(listOf("#111111", "#eeeeee", "nope")),
        )
        assertEquals(LazurePigments.ankyPaperDeep, LevelTheme.Fallback.backgroundWash)
        assertEquals(LazurePigments.ankyGold, LevelTheme.Fallback.glowTint)
        assertEquals(LazurePigments.ankyGoldLight, LevelTheme.Fallback.buttonWarmth)
    }

    @Test
    fun derivationMatchesTheIosMidGlowWarmthRules() {
        // Palette arrives sorted dark -> light (5 swatches: mid index 2).
        val palette = listOf("#101010", "#303030", "#606060", "#a0a0a0", "#e0e0c0")
        val theme = LevelTheme.fromPalette(palette)

        assertEquals(5, theme.swatches.size)
        val mid = checkNotNull(colorFromHexSwatch("#606060"))
        assertEquals(mid.copy(alpha = 0.35f), theme.backgroundWash)
        assertEquals(checkNotNull(colorFromHexSwatch("#e0e0c0")), theme.glowTint)
        assertEquals(checkNotNull(colorFromHexSwatch("#a0a0a0")), theme.buttonWarmth)
    }

    @Test
    fun wallMoodCarriesTheKingdomPigment() {
        assertEquals(LazureMood.Dawn, LevelTheme.Fallback.wallMood)
        val theme = LevelTheme.fromPalette(listOf("#101010", "#606060", "#e0e0c0"))
        val mood = theme.wallMood
        assertTrue(mood is LazureMood.Kingdom)
        assertEquals(theme.glowTint, (mood as LazureMood.Kingdom).pigment)
    }

    @Test
    fun moodPigmentTriplesMatchTheSwiftMapping() {
        assertEquals(
            Triple(LazurePigments.ankyApricot, LazurePigments.ankyGoldLight, LazurePigments.ankyViolet),
            LazureMood.Dawn.pigments,
        )
        assertEquals(
            Triple(LazurePigments.ankyViolet, LazurePigments.ankyRose, LazurePigments.ankySlate),
            LazureMood.Dusk.pigments,
        )
        assertEquals(
            Triple(LazurePigments.ankySage, LazurePigments.ankyGoldLight, LazurePigments.ankyViolet),
            LazureMood.Kingdom(LazurePigments.ankySage).pigments,
        )
    }
}
