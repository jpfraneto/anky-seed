package inc.anky.android.level

import inc.anky.android.core.level.journey.JourneyDayKind
import inc.anky.android.core.level.journey.JourneyPositions
import inc.anky.android.core.level.journey.JourneySessionInput
import inc.anky.android.core.level.journey.JourneySojourn
import inc.anky.android.core.level.journey.JourneyState
import java.io.File
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JourneyStateTest {
    private val zone = ZoneOffset.UTC
    private val dayMs = 86_400_000L

    // Noon UTC on a fixed day, so day arithmetic never straddles midnight.
    private val nowMs = (1_770_000_000_000 / dayMs) * dayMs + dayMs / 2

    private fun session(daysAgo: Int, durationMs: Long = 480_000) =
        JourneySessionInput(createdAtMs = nowMs - daysAgo * dayMs, durationMs = durationMs)

    @Test
    fun sojournConstantsMatchIos() {
        assertEquals(8, JourneySojourn.KingdomCount)
        assertEquals(8, JourneySojourn.TilesPerKingdom)
        assertEquals(4, JourneySojourn.ThresholdsPerKingdom)
        assertEquals(12, JourneySojourn.DaysPerKingdom)
        assertEquals(96, JourneySojourn.TotalDays)
    }

    @Test
    fun emptySessionsStartAtDayOne() {
        val snapshot = JourneyState.derive(emptyList(), nowMs = nowMs, zone = zone)
        assertEquals(0, snapshot.completedDays)
        assertEquals(1, snapshot.currentJourneyDay)
        assertEquals(0, snapshot.currentDayIndex)
        assertEquals(0, snapshot.streakDays)
        assertEquals(emptySet<Int>(), snapshot.writtenDayIndices)
        assertEquals(emptySet<Int>(), snapshot.missedDayIndices)
    }

    @Test
    fun distinctWritingDaysLightTheirIndicesAndMissedDaysStayDark() {
        // Wrote 4, 3, and 1 days ago (missed 2 days ago and today so far).
        val snapshot = JourneyState.derive(
            listOf(session(4), session(3), session(1), session(1)),
            nowMs = nowMs,
            zone = zone,
        )
        assertEquals(5, snapshot.currentJourneyDay) // first writing 4 days ago → day 5
        assertEquals(setOf(0, 1, 3), snapshot.writtenDayIndices)
        assertEquals(setOf(2, 4), snapshot.missedDayIndices)
        assertEquals(3, snapshot.completedDays)
        assertEquals(2, snapshot.currentDayIndex)
        assertEquals(4, snapshot.writingsCount)
        assertEquals(32, snapshot.minutesWritten) // 4 × 8 minutes
    }

    @Test
    fun streakCountsConsecutiveDaysEndingTodayOrYesterday() {
        val endingToday = JourneyState.derive(
            listOf(session(2), session(1), session(0)),
            nowMs = nowMs,
            zone = zone,
        )
        assertEquals(3, endingToday.streakDays)

        // A day in progress doesn't break its own streak.
        val endingYesterday = JourneyState.derive(
            listOf(session(2), session(1)),
            nowMs = nowMs,
            zone = zone,
        )
        assertEquals(2, endingYesterday.streakDays)

        val broken = JourneyState.derive(listOf(session(3), session(2)), nowMs = nowMs, zone = zone)
        assertEquals(0, broken.streakDays)
    }

    @Test
    fun journeyClampsAtNinetySixDaysAndNothingEverResets() {
        val sessions = (0 until 200).map { session(it) }
        val snapshot = JourneyState.derive(sessions, nowMs = nowMs, zone = zone)
        assertEquals(96, snapshot.currentJourneyDay)
        assertEquals(96, snapshot.completedDays)
        assertEquals(95, snapshot.currentDayIndex)
        assertTrue(snapshot.writtenDayIndices.all { it in 0 until 96 })
    }

    @Test
    fun authoredPositionsFileHoldsTheFullSojourn() {
        val json = journeyPositionsJson()
        val days = JourneyPositions.parse(json)
        assertEquals(JourneySojourn.TotalDays, days.size)
        days.forEachIndexed { index, day ->
            assertEquals(index, day.index)
            assertTrue(day.imageIndex in 0 until JourneySojourn.KingdomCount)
            assertTrue(day.kingdomIndex in 0 until JourneySojourn.KingdomCount)
            assertTrue(day.x in 0.0..1.0)
            assertTrue(day.y in 0.0..1.0)
        }
        // 8 tile + 4 threshold days per kingdom.
        (0 until JourneySojourn.KingdomCount).forEach { kingdom ->
            val kingdomDays = days.filter { it.kingdomIndex == kingdom }
            assertEquals(JourneySojourn.DaysPerKingdom, kingdomDays.size)
            assertEquals(JourneySojourn.TilesPerKingdom, kingdomDays.count { it.kind == JourneyDayKind.Tile })
            assertEquals(JourneySojourn.ThresholdsPerKingdom, kingdomDays.count { it.kind == JourneyDayKind.Threshold })
        }
    }

    @Test
    fun malformedPositionsParseToEmptyViaSoftPath() {
        assertEquals(emptyList<Any>(), JourneyPositions.parseOrEmpty(null))
        assertEquals(emptyList<Any>(), JourneyPositions.parseOrEmpty("{}"))
        assertEquals(emptyList<Any>(), JourneyPositions.parseOrEmpty("""{"version":1,"days":[]}"""))
    }

    private fun journeyPositionsJson(): String {
        // Walk up from the test working directory to the repo root, then read
        // the bundled asset exactly as shipped.
        var current = File(checkNotNull(System.getProperty("user.dir"))).canonicalFile
        while (current.parentFile != null) {
            val candidate = File(
                current,
                "apps/android/app/src/main/assets/${JourneyPositions.AssetPath}",
            )
            if (candidate.isFile) return candidate.readText(Charsets.UTF_8)
            current = current.parentFile
        }
        error("journey_positions.json asset not found")
    }
}
