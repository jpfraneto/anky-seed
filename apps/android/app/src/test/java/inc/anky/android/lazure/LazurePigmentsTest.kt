package inc.anky.android.lazure

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import inc.anky.android.ui.lazure.LazurePigments
import inc.anky.android.ui.lazure.LazureRoles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Verifies the 13 pigments against the exact Display-P3 literals in the
 * iOS source of truth (`AnkyLazure.swift` §1).
 */
class LazurePigmentsTest {

    // (name, color, iOS red, green, blue) — transcribed from AnkyLazure.swift.
    private val table = listOf(
        Entry("ankyPaper", LazurePigments.ankyPaper, 0.965f, 0.937f, 0.894f),
        Entry("ankyPaperDeep", LazurePigments.ankyPaperDeep, 0.929f, 0.882f, 0.835f),
        Entry("ankyInk", LazurePigments.ankyInk, 0.239f, 0.216f, 0.310f),
        Entry("ankyInkSoft", LazurePigments.ankyInkSoft, 0.396f, 0.369f, 0.475f),
        Entry("ankyUmber", LazurePigments.ankyUmber, 0.310f, 0.243f, 0.180f),
        Entry("ankySlate", LazurePigments.ankySlate, 0.353f, 0.427f, 0.514f),
        Entry("ankyViolet", LazurePigments.ankyViolet, 0.478f, 0.392f, 0.541f),
        Entry("ankyApricot", LazurePigments.ankyApricot, 0.918f, 0.741f, 0.573f),
        Entry("ankyGold", LazurePigments.ankyGold, 0.878f, 0.694f, 0.427f),
        Entry("ankyGoldLight", LazurePigments.ankyGoldLight, 0.965f, 0.847f, 0.631f),
        Entry("ankySage", LazurePigments.ankySage, 0.678f, 0.714f, 0.604f),
        Entry("ankyRose", LazurePigments.ankyRose, 0.851f, 0.671f, 0.647f),
        Entry("ankyMadder", LazurePigments.ankyMadder, 0.702f, 0.325f, 0.302f),
    )

    private data class Entry(
        val name: String,
        val color: Color,
        val red: Float,
        val green: Float,
        val blue: Float,
    )

    @Test
    fun thirteenPigmentsMatchTheSwiftDisplayP3LiteralsExactly() {
        assertEquals(13, table.size)
        // Wide-gamut Colors are packed as half-floats; allow F16 quantization.
        val tolerance = 0.001f
        table.forEach { entry ->
            assertEquals("${entry.name} red", entry.red, entry.color.red, tolerance)
            assertEquals("${entry.name} green", entry.green, entry.color.green, tolerance)
            assertEquals("${entry.name} blue", entry.blue, entry.color.blue, tolerance)
            assertEquals("${entry.name} alpha", 1f, entry.color.alpha, tolerance)
        }
    }

    @Test
    fun allPigmentsLiveInDisplayP3() {
        table.forEach { entry ->
            assertEquals("${entry.name} color space", ColorSpaces.DisplayP3, entry.color.colorSpace)
        }
    }

    @Test
    fun noPigmentIsPureWhiteOrPureBlack() {
        table.forEach { entry ->
            val components = listOf(entry.color.red, entry.color.green, entry.color.blue)
            assertTrue("${entry.name} must not be pure white", components.any { it < 0.99f })
            assertTrue("${entry.name} must not be pure black", components.any { it > 0.01f })
        }
    }

    @Test
    fun hairlineIsInkAtEightPercent() {
        val hairline = LazurePigments.hairline
        assertEquals(0.08f, hairline.alpha, 0.001f)
        assertEquals(LazurePigments.ankyInk.red, hairline.red, 0.0001f)
        assertEquals(LazurePigments.ankyInk.green, hairline.green, 0.0001f)
        assertEquals(LazurePigments.ankyInk.blue, hairline.blue, 0.0001f)
    }

    @Test
    fun rolesMirrorTheIosAnkyThemeRemap() {
        val roles = LazureRoles()
        assertEquals(LazurePigments.ankyPaper, roles.background)
        assertEquals(LazurePigments.ankyPaperDeep.copy(alpha = 0.62f), roles.panel)
        assertEquals(LazurePigments.ankyPaperDeep, roles.panelStrong)
        assertEquals(LazurePigments.ankyInk.copy(alpha = 0.10f), roles.border)
        assertEquals(LazurePigments.ankyGold, roles.gold)
        assertEquals(LazurePigments.ankyGoldLight, roles.goldBright)
        assertEquals(LazurePigments.ankyInk, roles.text)
        assertEquals(LazurePigments.ankyInkSoft, roles.textMuted)
        assertEquals(LazurePigments.ankySage, roles.success)
        assertEquals(LazurePigments.ankyMadder, roles.danger)
        assertNotEquals(Color.White, roles.background)
        assertNotEquals(Color.Black, roles.text)
    }
}
