package inc.anky.android.gate

import inc.anky.android.core.gate.EightDayGate
import inc.anky.android.core.gate.EightDayGateProgress
import inc.anky.android.core.gate.EightDayGateStore
import inc.anky.android.core.gate.GateState
import inc.anky.android.core.gate.SignalCalculator
import inc.anky.android.core.gate.UnlockState
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollEvent
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WritingAnchorStore
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of iOS SignalStateTests.swift (minus the WritingSessionEngine cases). */
class SignalStateTest {
    private val zone = ZoneOffset.UTC
    private val now = Instant.ofEpochSecond(1_770_000_000)

    private fun daysAgo(days: Int): Instant = now.minusSeconds(days * 24L * 60 * 60)

    // Signal percent

    @Test
    fun signalPercentGrowsWithStreakAndToday() {
        assertEquals(0, SignalCalculator.signalPercent(streakDays = 0, wroteToday = false))
        assertEquals(23, SignalCalculator.signalPercent(streakDays = 1, wroteToday = true))
        assertEquals(33, SignalCalculator.signalPercent(streakDays = 3, wroteToday = false))
        assertEquals(100, SignalCalculator.signalPercent(streakDays = 8, wroteToday = true))
        assertEquals(100, SignalCalculator.signalPercent(streakDays = 30, wroteToday = true))
    }

    // Streak

    @Test
    fun streakDaysCountsConsecutiveWritingDays() {
        assertEquals(0, SignalCalculator.streakDays(sessionDays = emptyList(), now = now, zoneId = zone))

        assertEquals(1, SignalCalculator.streakDays(sessionDays = listOf(now), now = now, zoneId = zone))

        assertEquals(
            3,
            SignalCalculator.streakDays(
                sessionDays = listOf(now, daysAgo(1), daysAgo(2)),
                now = now,
                zoneId = zone,
            ),
        )
    }

    @Test
    fun streakEndingYesterdayStillCounts() {
        assertEquals(
            2,
            SignalCalculator.streakDays(
                sessionDays = listOf(daysAgo(1), daysAgo(2)),
                now = now,
                zoneId = zone,
            ),
        )
    }

    @Test
    fun streakBrokenByGapResets() {
        assertEquals(
            0,
            SignalCalculator.streakDays(
                sessionDays = listOf(daysAgo(2), daysAgo(3)),
                now = now,
                zoneId = zone,
            ),
        )

        assertEquals(
            1,
            SignalCalculator.streakDays(
                sessionDays = listOf(now, daysAgo(2), daysAgo(3)),
                now = now,
                zoneId = zone,
            ),
        )
    }

    // Snapshot

    @Test
    fun snapshotReflectsActiveUnlock() {
        val unlockedUntil = now.plusSeconds(15 * 60)
        val gateState = GateState(
            selectedApplicationCount = 2,
            unlockTierRawValue = UnlockTier.Quick.rawValue,
            unlockedUntil = unlockedUntil,
            shieldActive = false,
        )

        val snapshot = SignalCalculator.snapshot(
            gateState = gateState,
            unlockState = UnlockState(grant = null, lastWroteAt = now),
            events = emptyList(),
            sessionDays = listOf(now),
            now = now,
            zoneId = zone,
        )

        assertTrue(snapshot.isGateConfigured)
        assertTrue(snapshot.isCurrentlyUnlocked)
        assertEquals(unlockedUntil, snapshot.unlockExpiresAt)
        assertEquals(UnlockTier.Quick, snapshot.unlockTier)
        assertTrue(snapshot.wroteToday)
        assertEquals(1, snapshot.currentStreakDays)
        assertEquals(2, snapshot.selectedApplicationCount)
    }

    @Test
    fun snapshotExpiredUnlockIsLocked() {
        val gateState = GateState(
            selectedApplicationCount = 1,
            unlockTierRawValue = UnlockTier.Daily.rawValue,
            unlockedUntil = now.minusSeconds(60),
            shieldActive = true,
        )

        val snapshot = SignalCalculator.snapshot(
            gateState = gateState,
            unlockState = UnlockState(grant = null, lastWroteAt = null),
            events = emptyList(),
            sessionDays = emptyList(),
            now = now,
            zoneId = zone,
        )

        assertFalse(snapshot.isCurrentlyUnlocked)
        assertNull(snapshot.unlockExpiresAt)
        assertNull(snapshot.unlockTier)
        assertTrue(snapshot.isShieldActive)
        assertFalse(snapshot.wroteToday)
        assertEquals(0, snapshot.signalPercent)
    }

    @Test
    fun snapshotCountsOnlyTodaysUnlockGrantedEvents() {
        val events = listOf(
            WriteBeforeScrollEvent(name = WriteBeforeScrollEventName.UnlockGranted, timestamp = now),
            WriteBeforeScrollEvent(
                name = WriteBeforeScrollEventName.UnlockGranted,
                timestamp = now.minusSeconds(3600),
            ),
            WriteBeforeScrollEvent(name = WriteBeforeScrollEventName.UnlockGranted, timestamp = daysAgo(1)),
            WriteBeforeScrollEvent(name = WriteBeforeScrollEventName.WritingStarted, timestamp = now),
        )

        val snapshot = SignalCalculator.snapshot(
            gateState = GateState(selectedApplicationCount = 1),
            unlockState = UnlockState(grant = null, lastWroteAt = null),
            events = events,
            sessionDays = emptyList(),
            now = now,
            zoneId = zone,
        )

        assertEquals(2, snapshot.gatesCompletedToday)
    }

    @Test
    fun snapshotWroteTodayFromSessionDaysAlone() {
        val snapshot = SignalCalculator.snapshot(
            gateState = GateState(),
            unlockState = UnlockState(grant = null, lastWroteAt = null),
            events = emptyList(),
            sessionDays = listOf(now.minusSeconds(120)),
            now = now,
            zoneId = zone,
        )

        assertTrue(snapshot.wroteToday)
        assertFalse(snapshot.isGateConfigured)
        assertEquals(23, snapshot.signalPercent)
    }

    // 8-Day Gate progress

    @Test
    fun eightDayGateProgressStartsOnDayOne() {
        val progress = EightDayGateProgress()
        assertEquals(1, progress.currentDayNumber)
        assertEquals("Write before one app.", EightDayGate.title(forDay = progress.currentDayNumber))
        assertFalse(progress.isComplete)
        assertEquals(0, progress.completedDayCount)
    }

    @Test
    fun eightDayGateProgressAdvancesToFirstIncompleteDay() {
        var progress = EightDayGateProgress()
        progress = progress.markCompleted(1, at = now)
        progress = progress.markCompleted(2, at = now)
        progress = progress.markCompleted(4, at = now)

        assertEquals(3, progress.currentDayNumber)
        assertEquals(3, progress.completedDayCount)
        assertFalse(progress.isComplete)
    }

    @Test
    fun eightDayGateCompletionDatesArePermanent() {
        var progress = EightDayGateProgress()
        progress = progress.markCompleted(1, at = now)
        progress = progress.markCompleted(1, at = now.plusSeconds(9999))

        assertEquals(now, progress.completionDate(1))
        assertEquals(1, progress.completions.size)
    }

    @Test
    fun eightDayGateIgnoresInvalidDays() {
        var progress = EightDayGateProgress()
        progress = progress.markCompleted(0, at = now)
        progress = progress.markCompleted(9, at = now)
        assertEquals(0, progress.completedDayCount)
    }

    @Test
    fun eightDayGateStorePersistsAcrossLoads() {
        val preferences = FakeSharedPreferences()
        val store = EightDayGateStore(preferences)

        store.markCompleted(3, at = now)

        val reloaded = EightDayGateStore(preferences).load()
        assertTrue(reloaded.isDayComplete(3))
        assertEquals(now, reloaded.completionDate(3))
    }

    @Test
    fun eightDayGateDerivesHonestlyTrackableDays() {
        val store = EightDayGateStore(FakeSharedPreferences())

        val progress = store.refreshDerivedCompletions(
            hasCompletedFirstGate = true,
            protectedTargetCount = 2,
            hasCompletedDailyUnlock = true,
            hasWrittenPastTarget = false,
            isGateOn = true,
            now = now,
        )

        assertTrue(progress.isDayComplete(1))
        assertTrue(progress.isDayComplete(2))
        assertTrue(progress.isDayComplete(3))
        assertFalse("archive echo is event-driven, not derived", progress.isDayComplete(4))
        assertFalse("morning protection is scaffolded", progress.isDayComplete(5))
        assertFalse("share is scaffolded", progress.isDayComplete(6))
        assertFalse(progress.isDayComplete(7))
        assertFalse("requires days 1-7 first", progress.isDayComplete(8))
        assertEquals(4, progress.currentDayNumber)
    }

    @Test
    fun eightDayGateDayEightRequiresAllPriorDaysAndActiveGate() {
        val store = EightDayGateStore(FakeSharedPreferences())

        store.markCompleted(4, at = now)
        store.markCompleted(5, at = now)
        store.markCompleted(6, at = now)

        val withoutGate = store.refreshDerivedCompletions(
            hasCompletedFirstGate = true,
            protectedTargetCount = 3,
            hasCompletedDailyUnlock = true,
            hasWrittenPastTarget = true,
            isGateOn = false,
            now = now,
        )
        assertTrue(withoutGate.isDayComplete(7))
        assertFalse(withoutGate.isDayComplete(8))

        val withGate = store.refreshDerivedCompletions(
            hasCompletedFirstGate = true,
            protectedTargetCount = 3,
            hasCompletedDailyUnlock = true,
            hasWrittenPastTarget = true,
            isGateOn = true,
            now = now,
        )
        assertTrue(withGate.isDayComplete(8))
        assertTrue(withGate.isComplete)
        assertEquals(8, withGate.currentDayNumber)
    }

    // Shield arrival message

    @Test
    fun shieldArrivalMessageUsesAnchorWhenAvailable() {
        val store = WritingAnchorStore(FakeSharedPreferences())

        assertEquals(
            "Write one true thing before the feed gets in.",
            store.shieldArrivalMessage,
        )

        store.save(writerName = "JP", anchorSentence = "I don't need to disappear right now.")
        assertEquals(
            "JP, remember: “I don't need to disappear right now.”\nWrite one true sentence to unlock.",
            store.shieldArrivalMessage,
        )
    }
}
