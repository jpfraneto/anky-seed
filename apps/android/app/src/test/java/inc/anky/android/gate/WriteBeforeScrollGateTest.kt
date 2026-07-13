package inc.anky.android.gate

import inc.anky.android.core.gate.GateState
import inc.anky.android.core.gate.GateWritingSnapshot
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockPolicy
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollSessionMetricTracker
import inc.anky.android.core.gate.WriteBeforeScrollUnlockSource
import inc.anky.android.core.gate.WriteBeforeScrollUnlockStateMachine
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the UnlockPolicy, metric-tracker, and unlock-state-machine cases
 * from iOS WriteBeforeScrollTests.swift. Where iOS drives a
 * WritingSessionEngine, these tests hand the tracker the equivalent
 * [GateWritingSnapshot] directly — the assertions are unchanged.
 */
class WriteBeforeScrollGateTest {
    private fun snapshot(text: String, elapsedMs: Long = 0): GateWritingSnapshot =
        GateWritingSnapshot(reconstructedText = text, elapsedMs = elapsedMs)

    // UnlockPolicy.grant

    @Test
    fun quickSentenceTriggersOnPunctuationOrWordCount() {
        // Terminal punctuation fires first.
        assertTrue(UnlockPolicy.hasCompletedQuickSentence("I am here."))
        // ~5-7 words fire without punctuation, whichever comes first.
        assertTrue(UnlockPolicy.hasCompletedQuickSentence("one two three four five six"))
        // Below both thresholds: not yet.
        assertFalse(UnlockPolicy.hasCompletedQuickSentence("one two three four five"))
        assertFalse(UnlockPolicy.hasCompletedQuickSentence("..."))
        // Gibberish passes — the cap is the limiter, not the content.
        assertTrue(UnlockPolicy.hasCompletedQuickSentence("asdf jkl qwer uiop zxcv bnm"))
    }

    @Test
    fun unlockPolicyGrantsQuickPassForCompletedSentence() {
        val now = Instant.ofEpochSecond(1_770_000_000)

        val grant = UnlockPolicy().grant(snapshot("One sentence."), at = now)

        assertNotNull(grant)
        assertEquals(UnlockTier.Quick, grant?.tier)
        assertEquals("quick pass", grant?.tier?.displayName)
        assertEquals(
            15L * 60,
            Duration.between(now, grant?.unlockedUntil).seconds,
        )
    }

    @Test
    fun unlockPolicyWithholdsQuickPassWhenPassesExhausted() {
        val now = Instant.ofEpochSecond(1_770_000_000)

        assertNull(UnlockPolicy().grant(snapshot("I am here."), at = now, quickPassesRemaining = 0))
    }

    @Test
    fun unlockPolicyGrantsDailyUnlockPastTargetEvenWithoutPasses() {
        val now = Instant.ofEpochSecond(1_770_000_180)

        val grant = UnlockPolicy().grant(
            snapshot("just lettersb", elapsedMs = 180_000),
            at = now,
            dailyTargetMs = 3 * 60_000,
            quickPassesRemaining = 0,
        )

        assertEquals(UnlockTier.Daily, grant?.tier)
    }

    // Phase-3: the Daily Unlock is part of the subscription. A free writer
    // past their target earns a Quick Pass (protection and passes are free
    // forever), never the day.
    @Test
    fun unlockPolicyWithholdsDailyUnlockWhenNotEntitled() {
        val now = Instant.ofEpochSecond(1_770_000_180)
        val atTarget = snapshot("I wrote all the way to my target today.b", elapsedMs = 180_000)

        val grant = UnlockPolicy().grant(
            atTarget,
            at = now,
            dailyTargetMs = 3 * 60_000,
            dailyUnlockEntitled = false,
        )
        assertEquals(UnlockTier.Quick, grant?.tier)

        assertNull(
            UnlockPolicy().grant(
                atTarget,
                at = now,
                dailyTargetMs = 3 * 60_000,
                quickPassesRemaining = 0,
                dailyUnlockEntitled = false,
            ),
        )
    }

    @Test
    fun unlockPolicyDoesNotGrantSentenceUnlockForFirstCharacter() {
        val now = Instant.ofEpochSecond(1_770_000_000)

        assertFalse(snapshot("x").hasCompletedSentence)
        assertNull(UnlockPolicy().grant(snapshot("x"), at = now))
    }

    @Test
    fun unlockPolicyGrantsSentenceUnlockOnlyForCompletedSentences() {
        val now = Instant.ofEpochSecond(1_770_000_000)
        val policy = UnlockPolicy()

        for (text in listOf(
            "I am here.",
            "I do not need to disappear right now.",
            "Why am I opening this?",
            "Enough!",
        )) {
            val grant = policy.grant(snapshot(text), at = now)
            assertNotNull("expected unlock for $text", grant)
            assertEquals("expected quick pass for $text", UnlockTier.Quick, grant?.tier)
            assertEquals(15L * 60, Duration.between(now, grant?.unlockedUntil).seconds)
        }

        for (text in listOf("h", "hello", "hello ", ".", "...", "!?", "     .", "I")) {
            assertFalse(
                "expected no completed sentence for $text",
                snapshot(text).hasCompletedSentence,
            )
            assertNull("expected no unlock for $text", policy.grant(snapshot(text), at = now))
        }
    }

    @Test
    fun unlockPolicyGrantsNothingForNonSentenceWritingBelowTarget() {
        val now = Instant.ofEpochSecond(1_770_000_088)

        assertNull(
            UnlockPolicy().grant(
                snapshot("just letters no punctuationb", elapsedMs = 88_000),
                at = now,
            ),
        )
    }

    @Test
    fun unlockPolicyCompletedSentenceBelowTargetGrantsQuickPass() {
        val now = Instant.ofEpochSecond(1_770_000_030)

        val grant = UnlockPolicy().grant(
            snapshot("I am here. And more.", elapsedMs = 30_000),
            at = now,
        )

        assertEquals(UnlockTier.Quick, grant?.tier)
    }

    @Test
    fun unlockPolicyDailyUnlockBeatsQuickPassAtTarget() {
        val now = Instant.ofEpochSecond(1_770_000_120)

        val grant = UnlockPolicy().grant(
            snapshot("I am here.b", elapsedMs = 120_000),
            at = now,
            dailyTargetMs = 2 * 60_000,
        )

        assertEquals(UnlockTier.Daily, grant?.tier)
    }

    @Test
    fun unlockPolicyGrantsDailyUnlockUntilEndOfLocalDay() {
        val zone = ZoneOffset.ofHours(-4)
        val now = Instant.ofEpochSecond(1_770_000_000)
        val expectedEndOfDay = now.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()

        val grant = UnlockPolicy(zone).grant(snapshot("ab", elapsedMs = 480_000), at = now)

        assertEquals(UnlockTier.Daily, grant?.tier)
        assertEquals("daily unlock", grant?.tier?.displayName)
        assertEquals(expectedEndOfDay, grant?.unlockedUntil)
    }

    @Test
    fun unlockPolicyHonorsCustomDailyTarget() {
        val now = Instant.ofEpochSecond(1_770_000_180)
        val threeMinutes = snapshot("ab", elapsedMs = 180_000)

        val grant = UnlockPolicy().grant(threeMinutes, at = now, dailyTargetMs = 3 * 60_000)
        assertEquals(UnlockTier.Daily, grant?.tier)

        assertNull(UnlockPolicy().grant(threeMinutes, at = now, dailyTargetMs = 4 * 60_000))
    }

    @Test
    fun unlockTierOrdering() {
        assertTrue(UnlockTier.Quick.unlockRank < UnlockTier.Daily.unlockRank)
    }

    // Metric tracker (the golden metric)

    @Test
    fun metricsTrackerDoesNotMarkSentenceUnlockForSingleCharacter() {
        val tracker = WriteBeforeScrollSessionMetricTracker()
        val start = Instant.ofEpochSecond(1_770_000_000)

        val update = tracker.recordAcceptedCharacters(
            count = 1,
            snapshot = snapshot("h"),
            at = start,
        )

        assertNull(update.availableGrant)
        assertNull(update.metrics.firstUnlockTier)
        assertFalse(update.metrics.hasQuickPassAvailable)
        assertFalse(update.events.contains(WriteBeforeScrollEventName.SentenceUnlockAvailable))
    }

    @Test
    fun metricsTrackerMarksSentenceUnlockAfterCompletedSentence() {
        val tracker = WriteBeforeScrollSessionMetricTracker()
        val start = Instant.ofEpochSecond(1_770_000_000)

        tracker.recordAcceptedCharacters(
            count = "I am here".length,
            snapshot = snapshot("I am here"),
            at = start,
        )
        assertFalse(tracker.metrics.hasQuickPassAvailable)

        val update = tracker.recordAcceptedCharacters(
            count = 1,
            snapshot = snapshot("I am here.", elapsedMs = 2_000),
            at = start.plusSeconds(2),
        )

        assertEquals(UnlockTier.Quick, update.availableGrant?.tier)
        assertEquals(UnlockTier.Quick, update.metrics.firstUnlockTier)
        assertTrue(update.metrics.hasQuickPassAvailable)
        assertTrue(update.events.contains(WriteBeforeScrollEventName.SentenceUnlockAvailable))
    }

    @Test
    fun continuedWritingAfterUnlockDetection() {
        val tracker = WriteBeforeScrollSessionMetricTracker()
        val start = Instant.ofEpochSecond(1_770_000_000)

        var update = tracker.recordAcceptedCharacters(
            count = "One sentence.".length,
            snapshot = snapshot("One sentence."),
            at = start,
        )

        assertEquals(UnlockTier.Quick, update.availableGrant?.tier)
        assertEquals(UnlockTier.Quick, update.metrics.firstUnlockTier)
        assertFalse(update.metrics.continuedWritingAfterUnlockAvailable)
        assertEquals(0, update.metrics.charactersAfterUnlockAvailable)

        update = tracker.recordAcceptedCharacters(
            count = " more".length,
            snapshot = snapshot("One sentence. more", elapsedMs = 5_000),
            at = start.plusSeconds(5),
        )

        assertTrue(update.metrics.continuedWritingAfterUnlockAvailable)
        assertEquals(5, update.metrics.charactersAfterUnlockAvailable)
        assertEquals(5.0, update.metrics.secondsWritingAfterUnlockAvailable, 0.001)
        assertTrue(update.events.contains(WriteBeforeScrollEventName.ContinuedWritingAfterUnlockAvailable))
    }

    @Test
    fun multiCharacterAppendCountsTowardDailyTarget() {
        val tracker = WriteBeforeScrollSessionMetricTracker()
        val now = Instant.ofEpochSecond(1_770_000_088)

        tracker.recordAcceptedCharacters(
            count = 1,
            snapshot = snapshot("a"),
            at = Instant.ofEpochSecond(1_770_000_000),
            dailyTargetMs = 88_000,
        )

        val update = tracker.recordAcceptedCharacters(
            count = 3,
            snapshot = snapshot("axyz", elapsedMs = 88_000),
            at = now,
            dailyTargetMs = 88_000,
        )

        assertEquals(UnlockTier.Daily, update.availableGrant?.tier)
        assertTrue(update.metrics.hasDailyUnlockAvailable)
        assertTrue(update.events.contains(WriteBeforeScrollEventName.DailyTargetReached))
        assertEquals(4, update.metrics.totalAcceptedCharacters)
    }

    @Test
    fun metricsTrackerWithholdsQuickPassWhenPassesExhausted() {
        val tracker = WriteBeforeScrollSessionMetricTracker()
        val start = Instant.ofEpochSecond(1_770_000_000)

        val update = tracker.recordAcceptedCharacters(
            count = "I am here.".length,
            snapshot = snapshot("I am here."),
            at = start,
            quickPassesRemaining = 0,
        )

        assertNull(update.availableGrant)
        assertFalse(update.metrics.hasQuickPassAvailable)
        assertFalse(update.events.contains(WriteBeforeScrollEventName.SentenceUnlockAvailable))
    }

    // Gate state machine

    @Test
    fun expirationLogicAndForceTransitions() {
        var state = GateState(
            selectedApplicationCount = 1,
            shieldActive = true,
        )
        val now = Instant.ofEpochSecond(1_770_000_000)
        val grant = UnlockGrant(
            tier = UnlockTier.Quick,
            unlockedUntil = now.plusSeconds(60),
            grantedAt = now,
        )

        state = WriteBeforeScrollUnlockStateMachine.applyingUnlock(
            tierRawValue = grant.tier.rawValue,
            unlockedUntil = grant.unlockedUntil,
            source = WriteBeforeScrollUnlockSource.Test,
            state = state,
        )

        assertEquals(UnlockTier.Quick.rawValue, state.unlockTierRawValue)
        assertEquals(WriteBeforeScrollUnlockSource.Test.rawValue, state.unlockSourceRawValue)
        assertFalse(state.shieldActive)
        assertTrue(state.isUnlocked(at = now.plusSeconds(59)))
        assertFalse(state.isUnlocked(at = now.plusSeconds(60)))

        state = WriteBeforeScrollUnlockStateMachine.forcingLock(state, at = now.plusSeconds(30))

        assertNull(state.unlockTierRawValue)
        assertNull(state.unlockedUntil)
        assertNull(state.unlockSourceRawValue)
        assertTrue(state.shieldActive)
        assertEquals(now.plusSeconds(30), state.lastRelockedAt)
    }
}
