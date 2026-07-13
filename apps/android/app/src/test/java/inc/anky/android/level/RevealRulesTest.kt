package inc.anky.android.level

import inc.anky.android.core.level.RevealRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The reveal rule from iOS `FallbackRevealRenderer`:
 * mask = clamp((progress − map) × 60). Ported as pure math so the rule is
 * asserted on the JVM; the Bitmap compositor applies it per pixel.
 */
class RevealRulesTest {
    @Test
    fun maskIsFullyHiddenWhereMapIsAheadOfProgress() {
        assertEquals(0.0, RevealRules.mask(progress = 0.0, mapValue = 0.5), 0.0)
        assertEquals(0.0, RevealRules.mask(progress = 0.5, mapValue = 0.5), 0.0)
        assertEquals(0.0, RevealRules.mask(progress = 0.5, mapValue = 0.9), 0.0)
    }

    @Test
    fun maskIsFullyRevealedOneSixtiethPastTheMapValue() {
        assertEquals(1.0, RevealRules.mask(progress = 0.5, mapValue = 0.5 - 1.0 / 60.0), 1e-9)
        assertEquals(1.0, RevealRules.mask(progress = 1.0, mapValue = 0.0), 0.0)
        assertEquals(1.0, RevealRules.mask(progress = 1.0, mapValue = 0.9), 0.0)
    }

    @Test
    fun maskFeathersLinearlyInsideTheWetEdge() {
        // Halfway into the 1/60 edge → mask 0.5.
        assertEquals(0.5, RevealRules.mask(progress = 0.5, mapValue = 0.5 - 0.5 / 60.0), 1e-9)
        // The edge is monotonic in progress.
        var last = -1.0
        var progress = 0.0
        while (progress <= 1.0) {
            val mask = RevealRules.mask(progress, mapValue = 0.4)
            assertTrue(mask >= last)
            assertTrue(mask in 0.0..1.0)
            last = mask
            progress += 0.01
        }
    }

    @Test
    fun zeroProgressShowsUnderdrawingFullProgressShowsFinal() {
        // Map value 0 is the very first stroke: it arrives as soon as
        // progress leaves zero, exactly like the shader path.
        assertEquals(0.0, RevealRules.mask(progress = 0.0, mapValue = 0.0), 0.0)
        assertTrue(RevealRules.mask(progress = 0.02, mapValue = 0.0) == 1.0)

        assertEquals(10, RevealRules.blendChannel(under = 10, final = 200, mask = 0.0))
        assertEquals(200, RevealRules.blendChannel(under = 10, final = 200, mask = 1.0))
        assertEquals(105, RevealRules.blendChannel(under = 10, final = 200, mask = 0.5))
    }

    @Test
    fun blendChannelStaysInByteRange() {
        assertEquals(0, RevealRules.blendChannel(under = 0, final = 0, mask = 0.7))
        assertEquals(255, RevealRules.blendChannel(under = 255, final = 255, mask = 0.3))
    }
}
