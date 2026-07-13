package inc.anky.android.level

import inc.anky.android.core.level.AnkyLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AnkyLevelTest {
    // Parity fixtures — the same values are asserted by the Swift implementation
    // (Tests/LevelTests.swift) and the TypeScript one (protocol test/level.test.ts).
    // If one side changes, all must.
    private val requirements = listOf<Long>(
        480, 778, 1260, 2041, 3306, 5356, 8677, 14057, 22772, 36891, 59763, 96816,
    )
    private val thresholds = listOf<Long>(
        0, 480, 1258, 2518, 4559, 7865, 13221, 21898, 35955, 58727, 95618, 155381,
    )

    @Test
    fun levelOneToTwoCostsExactly480Seconds() {
        assertEquals(480, AnkyLevel.BaseSeconds)
        assertEquals(480L, AnkyLevel.requirementSeconds(1))
        assertEquals(480L, AnkyLevel.thresholdSeconds(2))
        assertEquals(1, AnkyLevel.level(479))
        assertEquals(2, AnkyLevel.level(480))
    }

    @Test
    fun requirementsAndThresholdsMatchParityFixtures() {
        requirements.forEachIndexed { index, want ->
            assertEquals(want, AnkyLevel.requirementSeconds(index + 1))
        }
        thresholds.forEachIndexed { index, want ->
            assertEquals(want, AnkyLevel.thresholdSeconds(index + 1))
        }
    }

    @Test
    fun progressIsMonotonicAndNeverDecays() {
        var lastLevel = 1
        var total = 0L
        while (total <= 10_000) {
            val progress = AnkyLevel.progress(total)
            assertTrue(progress.level >= lastLevel)
            assertTrue(progress.secondsIntoLevel >= 0)
            assertTrue(progress.secondsIntoLevel <= progress.secondsRequired)
            assertTrue(progress.percent >= 0)
            assertTrue(progress.percent <= 1)
            lastLevel = progress.level
            total += 97
        }
    }

    @Test
    fun progressAtExactBoundaries() {
        val atBoundary = AnkyLevel.progress(480)
        assertEquals(2, atBoundary.level)
        assertEquals(0L, atBoundary.secondsIntoLevel)
        assertEquals(778L, atBoundary.secondsRequired)
        assertEquals(0.0, atBoundary.percent, 0.0)

        val justBefore = AnkyLevel.progress(479)
        assertEquals(1, justBefore.level)
        assertEquals(479L, justBefore.secondsIntoLevel)
    }

    @Test
    fun negativeInputClampsSanely() {
        assertEquals(1, AnkyLevel.level(-100))
        assertEquals(0L, AnkyLevel.progress(-100).secondsIntoLevel)
    }

    @Test
    fun levelIsBoundedForAnyRepresentableTotal() {
        val level = AnkyLevel.level(Long.MAX_VALUE)
        assertTrue(level <= AnkyLevel.MaxLevel)
        // the geometric curve outruns 2^53 seconds long before maxLevel
        assertTrue(level > 60)
        assertTrue(AnkyLevel.progress(Long.MAX_VALUE).percent <= 1)
    }
}
