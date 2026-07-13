package inc.anky.android.gate

import inc.anky.android.core.gate.DailyTargetStore
import inc.anky.android.core.gate.FirstGateStore
import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.QuickPassStore
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockState
import inc.anky.android.core.gate.UnlockStateStore
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollUnlockOfferPolicy
import inc.anky.android.core.gate.WritingAnchorStore
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the persistence-facing cases from iOS WriteBeforeScrollTests.swift
 * (UnlockStateStore, offer policy, QuickPassStore, DailyTargetStore,
 * FirstGateStore, WritingAnchorStore) plus event-log invariants.
 */
class GateStoresTest {
    private val zone = ZoneOffset.UTC

    // UnlockStateStore

    @Test
    fun unlockStateStorePersistsGrantAndWroteToday() {
        val preferences = FakeSharedPreferences()
        val store = UnlockStateStore(preferences)
        val now = Instant.ofEpochSecond(1_770_000_000)
        val grant = UnlockGrant(
            tier = UnlockTier.Quick,
            unlockedUntil = now.plusSeconds(900),
            grantedAt = now,
        )

        store.apply(grant)

        val state = UnlockStateStore(preferences).load()
        assertEquals(grant, state.grant)
        assertTrue(state.isUnlocked(at = now.plusSeconds(899)))
        assertFalse(state.isUnlocked(at = now.plusSeconds(900)))
        assertTrue(state.wroteToday(at = now, zoneId = zone))
    }

    @Test
    fun unlockStateStoreClearUnlockKeepsWritingDateByDefault() {
        val store = UnlockStateStore(FakeSharedPreferences())
        val now = Instant.ofEpochSecond(1_770_000_000)
        store.apply(
            UnlockGrant(tier = UnlockTier.Quick, unlockedUntil = now.plusSeconds(900), grantedAt = now),
        )

        store.clearUnlock()
        assertNull(store.load().grant)
        assertEquals(now, store.load().lastWroteAt)

        store.clearUnlock(keepWritingDate = false)
        assertNull(store.load().lastWroteAt)
    }

    // Offer policy

    @Test
    fun unlockOfferPolicySuppressesCTAWhileAppsAreUnlocked() {
        val now = Instant.ofEpochSecond(1_770_000_000)
        val state = UnlockState(
            grant = UnlockGrant(
                tier = UnlockTier.Quick,
                unlockedUntil = now.plusSeconds(900),
                grantedAt = now,
            ),
            lastWroteAt = now,
        )

        assertFalse(WriteBeforeScrollUnlockOfferPolicy().shouldOfferUnlock(state, at = now.plusSeconds(60)))
    }

    @Test
    fun unlockOfferPolicyAllowsCTAAfterTemporaryUnlockExpires() {
        val now = Instant.ofEpochSecond(1_770_000_000)
        val state = UnlockState(
            grant = UnlockGrant(
                tier = UnlockTier.Quick,
                unlockedUntil = now.plusSeconds(1_800),
                grantedAt = now,
            ),
            lastWroteAt = now,
        )

        assertTrue(WriteBeforeScrollUnlockOfferPolicy().shouldOfferUnlock(state, at = now.plusSeconds(1_801)))
    }

    @Test
    fun unlockOfferPolicyAllowsCTAWhenNoUnlockExists() {
        val state = UnlockState(grant = null, lastWroteAt = null)

        assertTrue(WriteBeforeScrollUnlockOfferPolicy().shouldOfferUnlock(state))
    }

    // QuickPassStore

    @Test
    fun quickPassStoreGrantsThreePassesAndTracksNumbers() {
        val store = QuickPassStore(FakeSharedPreferences())
        val now = Instant.ofEpochSecond(1_770_000_000)

        assertEquals(3, store.remainingPasses(now = now, zoneId = zone))
        assertEquals(1, store.consumePass(now = now, zoneId = zone))
        assertEquals(2, store.consumePass(now = now, zoneId = zone))
        assertEquals(1, store.remainingPasses(now = now, zoneId = zone))
        assertEquals(3, store.consumePass(now = now, zoneId = zone))
        assertEquals(0, store.remainingPasses(now = now, zoneId = zone))
        assertNull(store.consumePass(now = now, zoneId = zone))
    }

    @Test
    fun quickPassStoreResetsAtLocalMidnight() {
        val store = QuickPassStore(FakeSharedPreferences())
        val today = Instant.ofEpochSecond(1_770_000_000)
        val tomorrow = today.plusSeconds(24 * 60 * 60)

        store.consumePass(now = today, zoneId = zone)
        store.consumePass(now = today, zoneId = zone)
        store.consumePass(now = today, zoneId = zone)
        assertEquals(0, store.remainingPasses(now = today, zoneId = zone))

        assertEquals(3, store.remainingPasses(now = tomorrow, zoneId = zone))
        assertEquals(1, store.consumePass(now = tomorrow, zoneId = zone))
    }

    // DailyTargetStore

    @Test
    fun dailyTargetStoreDefaultsToEightMinutes() {
        val store = DailyTargetStore(FakeSharedPreferences())

        assertEquals(8, store.effectiveTargetMinutes())
        assertEquals(480_000L, store.effectiveTargetMs())
    }

    @Test
    fun dailyTargetStoreInitialSetAppliesImmediatelyAndClamps() {
        val store = DailyTargetStore(FakeSharedPreferences())

        store.setInitialTarget(3)
        assertEquals(3, store.effectiveTargetMinutes())

        store.setInitialTarget(0)
        assertEquals(1, store.effectiveTargetMinutes())

        store.setInitialTarget(99)
        assertEquals(8, store.effectiveTargetMinutes())
    }

    @Test
    fun dailyTargetStoreEditsTakeEffectNextDay() {
        val store = DailyTargetStore(FakeSharedPreferences())
        val today = Instant.ofEpochSecond(1_770_000_000)
            .atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
            .plusSeconds(9 * 3600)
        val laterToday = today.plusSeconds(3600)
        val tomorrow = today.plusSeconds(24 * 60 * 60)

        store.setInitialTarget(8)
        val change = store.requestTargetChange(3, now = today, zoneId = zone)
        assertEquals(8, change.oldMinutes)
        assertEquals(3, change.newMinutes)

        assertEquals(
            "edit must not apply mid-day",
            8,
            store.effectiveTargetMinutes(now = laterToday, zoneId = zone),
        )
        assertEquals(3, store.pendingTargetMinutes(now = laterToday, zoneId = zone))

        assertEquals(
            "edit applies the next day",
            3,
            store.effectiveTargetMinutes(now = tomorrow, zoneId = zone),
        )
        assertNull(store.pendingTargetMinutes(now = tomorrow, zoneId = zone))
    }

    @Test
    fun dailyTargetStoreRequestingCurrentValueCancelsPendingChange() {
        val store = DailyTargetStore(FakeSharedPreferences())
        val today = Instant.ofEpochSecond(1_770_000_000)
            .atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
            .plusSeconds(9 * 3600)
        val tomorrow = today.plusSeconds(24 * 60 * 60)

        store.setInitialTarget(8)
        store.requestTargetChange(3, now = today, zoneId = zone)
        store.requestTargetChange(8, now = today, zoneId = zone)

        assertNull(store.pendingTargetMinutes(now = today, zoneId = zone))
        assertEquals(8, store.effectiveTargetMinutes(now = tomorrow, zoneId = zone))
    }

    // FirstGateStore

    @Test
    fun firstGateStoreTracksCompletionAndPaywallHook() {
        val store = FirstGateStore(FakeSharedPreferences())

        assertFalse(store.hasCompletedFirstGate)
        assertFalse(store.shouldShowPostFirstGatePaywall)

        store.markFirstGateCompleted()
        assertTrue(store.hasCompletedFirstGate)
        assertTrue(store.shouldShowPostFirstGatePaywall)

        store.markPostFirstGatePaywallSeen()
        assertTrue(store.hasCompletedFirstGate)
        assertFalse(store.shouldShowPostFirstGatePaywall)
    }

    // WritingAnchorStore

    @Test
    fun writingAnchorStorePersistsAndNormalizesLocally() {
        val store = WritingAnchorStore(FakeSharedPreferences())

        assertEquals("You", store.writerName)
        assertNull(store.anchorSentence)
        assertNull(store.anchorReminderLine)

        store.save(writerName = "  JP  ", anchorSentence = " I don't need to disappear right now. ")
        assertEquals("JP", store.writerName)
        assertEquals("I don't need to disappear right now.", store.anchorSentence)
        assertEquals(
            "JP, remember: “I don't need to disappear right now.”",
            store.anchorReminderLine,
        )

        store.save(writerName = "   ", anchorSentence = "Stay here.")
        assertEquals("You", store.writerName)
        assertEquals("You, remember: “Stay here.”", store.anchorReminderLine)

        store.save(writerName = null, anchorSentence = null)
        assertEquals("You", store.writerName)
        assertNull(store.anchorSentence)
        assertNull(store.anchorReminderLine)
    }

    // GateStateStore

    @Test
    fun gateStateStoreRoundTripsAndStampsUpdatedAt() {
        val preferences = FakeSharedPreferences()
        val now = Instant.ofEpochSecond(1_770_000_000)
        val store = GateStateStore(preferences, now = { now })

        store.update { state ->
            state.copy(
                selectedApplicationCount = 3,
                shieldActive = true,
                unlockTierRawValue = UnlockTier.Quick.rawValue,
                unlockedUntil = now.plusSeconds(900),
                lastErrorMessage = "boom",
            )
        }

        val reloaded = GateStateStore(preferences).load()
        assertEquals(3, reloaded.selectedApplicationCount)
        assertTrue(reloaded.shieldActive)
        assertTrue(reloaded.hasSelection)
        assertEquals(UnlockTier.Quick.rawValue, reloaded.unlockTierRawValue)
        assertEquals(now.plusSeconds(900), reloaded.unlockedUntil)
        assertEquals("boom", reloaded.lastErrorMessage)
        assertEquals(now, reloaded.updatedAt)
        assertTrue(reloaded.isUnlocked(at = now))
        assertFalse(reloaded.isUnlocked(at = now.plusSeconds(900)))
    }

    // Event log

    @Test
    fun eventLogStoreAppendsAndCapsAtMaxStoredEvents() {
        val store = WriteBeforeScrollEventLogStore(FakeSharedPreferences())
        val start = Instant.ofEpochSecond(1_770_000_000)

        repeat(305) { index ->
            store.append(
                WriteBeforeScrollEventName.UnlockGranted,
                at = start.plusSeconds(index.toLong()),
                tierRawValue = UnlockTier.Quick.rawValue,
                metadata = mapOf("index" to "$index"),
            )
        }

        val events = store.load()
        assertEquals(300, events.size)
        assertEquals("5", events.first().metadata["index"])
        assertEquals("304", events.last().metadata["index"])
        assertEquals(UnlockTier.Quick.rawValue, events.last().tierRawValue)

        val recent = store.recent(limit = 20)
        assertEquals(20, recent.size)
        assertEquals("304", recent.first().metadata["index"])

        store.clear()
        assertTrue(store.load().isEmpty())
    }

    @Test
    fun eventLogShieldEventsAreTransitionOnly() {
        val store = WriteBeforeScrollEventLogStore(FakeSharedPreferences())
        val now = Instant.ofEpochSecond(1_770_000_000)

        store.appendShieldTransition(wasShieldActive = false, isShieldActive = true, at = now)
        store.appendShieldTransition(wasShieldActive = true, isShieldActive = true, at = now)
        store.appendShieldTransition(wasShieldActive = true, isShieldActive = false, at = now)
        store.appendShieldTransition(wasShieldActive = false, isShieldActive = false, at = now)

        assertEquals(
            listOf(
                WriteBeforeScrollEventName.ShieldApplied,
                WriteBeforeScrollEventName.ShieldCleared,
            ),
            store.load().map { it.name },
        )
    }
}
