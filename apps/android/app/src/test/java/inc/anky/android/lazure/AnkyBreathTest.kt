package inc.anky.android.lazure

import inc.anky.android.ui.lazure.AnkyBreath
import inc.anky.android.ui.lazure.LazureSeededRandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AnkyBreathTest {

    @Test
    fun cycleIsEightSeconds() {
        assertEquals(8_000L, AnkyBreath.CYCLE_MILLIS)
    }

    @Test
    fun phaseIsEasedZeroToOneToZero() {
        assertEquals(0f, AnkyBreath.phase(0L), 1e-6f)
        assertEquals(0.5f, AnkyBreath.phase(2_000L), 1e-6f)
        assertEquals(1f, AnkyBreath.phase(4_000L), 1e-6f)
        assertEquals(0.5f, AnkyBreath.phase(6_000L), 1e-6f)
        assertEquals(0f, AnkyBreath.phase(8_000L), 1e-6f)
    }

    @Test
    fun phaseHasNoJoltAtTheLoopPoint() {
        // The cosine easing makes the loop seam smooth: values just before
        // and after a cycle boundary are both near zero.
        assertEquals(AnkyBreath.phase(7_999L), AnkyBreath.phase(8_001L), 1e-6f)
        assertTrue(AnkyBreath.phase(7_999L) < 0.001f)
    }

    @Test
    fun phaseIsSharedWallClockAcrossComponents() {
        // Any two observers asking at the same instant get the same phase,
        // regardless of when they started observing.
        val t = 123_456_789L
        assertEquals(AnkyBreath.phase(t), AnkyBreath.phase(t + 5 * AnkyBreath.CYCLE_MILLIS), 1e-6f)
    }

    @Test
    fun phaseStaysInUnitRangeAndHandlesNegativeTime() {
        for (t in -20_000L..20_000L step 137) {
            val p = AnkyBreath.phase(t)
            assertTrue("phase($t) = $p out of range", p in 0f..1f)
        }
    }
}

class LazureSeededRandomTest {

    @Test
    fun sameSeedYieldsSameSequence() {
        val a = LazureSeededRandom(888L)
        val b = LazureSeededRandom(888L)
        repeat(1_000) {
            assertEquals(a.next(), b.next(), 0f)
        }
    }

    @Test
    fun valuesStayInUnitRange() {
        val rng = LazureSeededRandom(888L)
        repeat(10_000) {
            val v = rng.next()
            assertTrue(v in 0f..1f)
        }
    }

    @Test
    fun grainDensityMatchesTheIosThreshold() {
        // iOS keeps cells where v > 0.72 — about 28% of the sheet.
        val rng = LazureSeededRandom(888L)
        val samples = 100_000
        val specks = (0 until samples).count { rng.next() > 0.72f }
        val density = specks.toFloat() / samples
        assertTrue("density $density should be ~0.28", density in 0.26f..0.30f)
    }
}
