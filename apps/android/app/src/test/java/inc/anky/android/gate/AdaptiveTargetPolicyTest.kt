package inc.anky.android.gate

import inc.anky.android.core.gate.AdaptiveTargetOffer
import inc.anky.android.core.gate.AdaptiveTargetOfferStore
import inc.anky.android.core.gate.AdaptiveTargetPolicy
import inc.anky.android.core.storage.SessionSummary
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS AdaptiveTargetPolicyTests.swift. */
class AdaptiveTargetPolicyTest {
    private val zone = ZoneOffset.UTC
    private val now: Instant =
        LocalDateTime.of(2026, 7, 5, 14, 0).atZone(zone).toInstant()
    private val firstOpen: Instant =
        now.atZone(zone).toLocalDate().minusDays(30).atStartOfDay(zone).toInstant()

    private fun session(daysAgo: Int, minutes: Double): SessionSummary {
        val day: LocalDate = now.atZone(zone).toLocalDate().minusDays(daysAgo.toLong())
        val createdAt = day.atStartOfDay(zone).plusHours(10).toInstant()
        return SessionSummary(
            hash = UUID.randomUUID().toString(),
            createdAt = createdAt,
            localFilePath = "/tmp/test.anky",
            durationMs = (minutes * 60_000).toLong(),
            isComplete = minutes >= 8,
            preview = "test",
            wordCount = 1,
            hasReflection = false,
            reflectionTitle = null,
        )
    }

    private fun evaluate(sessions: List<SessionSummary>, target: Int = 8): AdaptiveTargetOffer? =
        AdaptiveTargetPolicy.evaluate(
            sessions = sessions,
            currentTargetMinutes = target,
            firstOpenDate = firstOpen,
            now = now,
            zoneId = zone,
        )

    @Test
    fun twoConsecutiveMissesOfferLowerTarget() {
        val sessions = listOf(
            session(daysAgo = 3, minutes = 8.0), // hit — ends the run
            session(daysAgo = 2, minutes = 3.0), // missed
            session(daysAgo = 1, minutes = 2.0), // missed
        )
        val offer = evaluate(sessions)
        assertNotNull(offer)
        assertEquals(8, offer?.currentTargetMinutes)
        assertEquals(4, offer?.suggestedTargetMinutes)
    }

    @Test
    fun singleMissIsNotAnEpisode() {
        val sessions = listOf(
            session(daysAgo = 2, minutes = 8.0),
            session(daysAgo = 1, minutes = 3.0),
        )
        assertNull(evaluate(sessions))
    }

    @Test
    fun todayIsNeverJudged() {
        // Missed yesterday and wrote nothing yet today: run length is 1.
        val sessions = listOf(
            session(daysAgo = 2, minutes = 8.0),
            session(daysAgo = 1, minutes = 1.0),
        )
        assertNull(evaluate(sessions))
    }

    @Test
    fun daysWithNoWritingCountAsMissed() {
        // Wrote 4 days ago, then silence — yesterday and the day before are
        // missing entirely, which is still a missed run of >= 2.
        val sessions = listOf(session(daysAgo = 4, minutes = 8.0))
        assertNotNull(evaluate(sessions))
    }

    @Test
    fun multipleShortSessionsDoNotSumIntoAHit() {
        // Daily Unlock needs one session at the target; three 3-minute
        // sessions do not open the door, so the day is missed.
        val shortDay2 = listOf(
            session(daysAgo = 2, minutes = 3.0),
            session(daysAgo = 2, minutes = 3.0),
            session(daysAgo = 2, minutes = 3.0),
        )
        val sessions = shortDay2 + session(daysAgo = 1, minutes = 3.0)
        assertNotNull(evaluate(sessions))
    }

    @Test
    fun episodeKeyIsStableWhileRunGrows() {
        val base = listOf(
            session(daysAgo = 3, minutes = 2.0),
            session(daysAgo = 2, minutes = 2.0),
        )
        val earlier = now.atZone(zone).minusDays(1).toInstant()
        val offerEarlier = AdaptiveTargetPolicy.evaluate(
            sessions = base,
            currentTargetMinutes = 8,
            firstOpenDate = firstOpen,
            now = earlier,
            zoneId = zone,
        )
        val offerLater = evaluate(base + session(daysAgo = 1, minutes = 2.0))
        assertNotNull(offerEarlier)
        assertEquals(offerEarlier?.episodeKey, offerLater?.episodeKey)
    }

    @Test
    fun hitDayStartsAFreshEpisodeKey() {
        val firstEpisode = evaluate(
            listOf(
                session(daysAgo = 5, minutes = 2.0),
                session(daysAgo = 4, minutes = 2.0),
            ),
        )
        val secondEpisode = evaluate(
            listOf(
                session(daysAgo = 5, minutes = 2.0),
                session(daysAgo = 4, minutes = 2.0),
                session(daysAgo = 3, minutes = 8.0), // hit — episode over
                session(daysAgo = 2, minutes = 2.0),
                session(daysAgo = 1, minutes = 2.0),
            ),
        )
        assertNotNull(firstEpisode)
        assertNotNull(secondEpisode)
        assertNotEquals(firstEpisode?.episodeKey, secondEpisode?.episodeKey)
    }

    @Test
    fun suggestionFloorsAtOneMinute() {
        assertEquals(4, AdaptiveTargetPolicy.suggestedMinutes(halving = 8))
        assertEquals(3, AdaptiveTargetPolicy.suggestedMinutes(halving = 5))
        assertEquals(1, AdaptiveTargetPolicy.suggestedMinutes(halving = 2))
    }

    @Test
    fun noOfferAtOneMinuteTarget() {
        val sessions = listOf(
            session(daysAgo = 2, minutes = 0.2),
            session(daysAgo = 1, minutes = 0.2),
        )
        assertNull(evaluate(sessions, target = 1))
    }

    @Test
    fun noOfferForSomeoneWhoNeverWrote() {
        assertNull(evaluate(emptyList()))
    }

    @Test
    fun offerStoreShowsOncePerEpisode() {
        val store = AdaptiveTargetOfferStore(FakeSharedPreferences())

        assertFalse(store.hasShown(episodeKey = "2026-07-03"))
        store.markShown(episodeKey = "2026-07-03")
        assertTrue(store.hasShown(episodeKey = "2026-07-03"))
        assertFalse(store.hasShown(episodeKey = "2026-07-06"))
    }
}
