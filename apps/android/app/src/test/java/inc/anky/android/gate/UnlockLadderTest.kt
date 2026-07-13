package inc.anky.android.gate

import inc.anky.android.core.gate.FreeTargetMomentLedger
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockPolicy
import inc.anky.android.core.gate.UnlockState
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollUnlockLadder
import inc.anky.android.core.gate.WriteBeforeScrollUnlockLadderAction
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The per-keystroke unlock ladder resolution (Fixes 3 and 4 of the
 * 2026-07-06 pre-submission audit): the Daily Unlock is never discarded
 * because a Quick Pass already opened the shield, and organic sessions
 * never surface or spend a Quick Pass.
 *
 * Port of iOS UnlockLadderTests.swift.
 */
class UnlockLadderTest {
    private val ladder = WriteBeforeScrollUnlockLadder()
    private val now = Instant.ofEpochSecond(1_780_000_000)

    private fun quickGrant(startingAt: Instant): UnlockGrant =
        UnlockGrant(
            tier = UnlockTier.Quick,
            unlockedUntil = startingAt.plusSeconds(UnlockPolicy.QuickPassUnlockSeconds),
            grantedAt = startingAt,
        )

    private fun dailyGrant(at: Instant): UnlockGrant =
        UnlockGrant(
            tier = UnlockTier.Daily,
            unlockedUntil = at.plusSeconds(6 * 60 * 60),
            grantedAt = at,
        )

    private val lockedState = UnlockState(grant = null, lastWroteAt = null)

    private val activeQuickPassState =
        UnlockState(grant = quickGrant(startingAt = now.minusSeconds(60)), lastWroteAt = now)

    private val expiredQuickPassState = UnlockState(
        grant = quickGrant(startingAt = now.minusSeconds(UnlockPolicy.QuickPassUnlockSeconds + 120)),
        lastWroteAt = now,
    )

    // Fix 3 — the daily grant survives an active Quick Pass

    @Test
    fun dailyGrantIsOfferedWhenNoPassWasUsed() {
        val grant = dailyGrant(at = now)
        val action = ladder.action(
            grant = grant,
            unlockState = lockedState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Offer(grant), action)
    }

    @Test
    fun dailyGrantUpgradesInPlaceWhileQuickPassIsActive() {
        val grant = dailyGrant(at = now)
        val action = ladder.action(
            grant = grant,
            unlockState = activeQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.UpgradeToDaily(grant), action)
    }

    @Test
    fun dailyGrantIsOfferedWhenQuickPassExpiredMidSession() {
        val grant = dailyGrant(at = now)
        val action = ladder.action(
            grant = grant,
            unlockState = expiredQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Offer(grant), action)
    }

    @Test
    fun dailyUpgradeIsIdempotentWithinASession() {
        val grant = dailyGrant(at = now)
        val action = ladder.action(
            grant = grant,
            unlockState = activeQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = true,
            at = now,
        )
        assertEquals(
            "a second crossing must not re-apply the upgrade",
            WriteBeforeScrollUnlockLadderAction.Offer(grant),
            action,
        )
    }

    @Test
    fun dailyUpgradeIsIdempotentAcrossSessionsInOneDay() {
        // Second session of the day: the daily unlock is already active.
        val grant = dailyGrant(at = now)
        val dailyUnlockedState = UnlockState(
            grant = dailyGrant(at = now.minusSeconds(3_600)),
            lastWroteAt = now,
        )
        val action = ladder.action(
            grant = grant,
            unlockState = dailyUnlockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(
            "an active daily unlock is never upgraded again",
            WriteBeforeScrollUnlockLadderAction.Offer(grant),
            action,
        )
    }

    // Fix 4 — organic sessions never surface or spend a Quick Pass

    @Test
    fun organicSessionWithdrawsQuickGrantWhileLocked() {
        val action = ladder.action(
            grant = quickGrant(startingAt = now),
            unlockState = lockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(
            "an organic session must not trigger the passive pass spend",
            WriteBeforeScrollUnlockLadderAction.Withdraw,
            action,
        )
    }

    @Test
    fun organicSessionWithdrawsQuickGrantWhileUnlocked() {
        val action = ladder.action(
            grant = quickGrant(startingAt = now),
            unlockState = activeQuickPassState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Withdraw, action)
    }

    @Test
    fun organicSessionStillEarnsTheDailyUnlock() {
        // Organic writing counts toward the daily target; only Quick Passes
        // are gate-exclusive.
        val grant = dailyGrant(at = now)
        val action = ladder.action(
            grant = grant,
            unlockState = lockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Offer(grant), action)
    }

    @Test
    fun gateSessionAppliesQuickPassPassively() {
        val grant = quickGrant(startingAt = now)
        val action = ladder.action(
            grant = grant,
            unlockState = lockedState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.ApplyQuickPassively(grant), action)
    }

    @Test
    fun gateSessionNeverAppliesQuickPassTwice() {
        val grant = quickGrant(startingAt = now)
        val action = ladder.action(
            grant = grant,
            unlockState = expiredQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(
            "a re-earned quick grant is offered, never auto-spent again",
            WriteBeforeScrollUnlockLadderAction.Offer(grant),
            action,
        )
    }

    @Test
    fun noGrantWithdraws() {
        val action = ladder.action(
            grant = null,
            unlockState = lockedState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Withdraw, action)
    }

    // The free-tier target moment (decision 2026-07-06, option C): a free or
    // lapsed writer's target crossing surfaces the moment screen once per
    // day; subscriber behavior is untouched.

    @Test
    fun freeWriterAtTargetGetsTheMomentScreen() {
        val action = ladder.action(
            grant = null,
            unlockState = lockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = false,
            hasReachedDailyTarget = true,
            hasOfferedFreeTargetMoment = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.OfferFreeTargetMoment, action)
    }

    @Test
    fun freeWriterAtTargetWithActiveQuickPassStillGetsTheMoment() {
        // The common shape: gate session, pass applied at ~6 words, target
        // crossed minutes later while the window is open.
        val action = ladder.action(
            grant = quickGrant(startingAt = now),
            unlockState = activeQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = false,
            hasReachedDailyTarget = true,
            hasOfferedFreeTargetMoment = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.OfferFreeTargetMoment, action)
    }

    @Test
    fun subscriberAtTargetIsUnchangedByTheMomentBranch() {
        // Entitled + reached target: exactly the pre-existing upgrade/offer
        // behavior, whatever the moment flags say.
        val grant = dailyGrant(at = now)
        val upgraded = ladder.action(
            grant = grant,
            unlockState = activeQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = true,
            hasReachedDailyTarget = true,
            hasOfferedFreeTargetMoment = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.UpgradeToDaily(grant), upgraded)

        val offered = ladder.action(
            grant = grant,
            unlockState = lockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = true,
            hasReachedDailyTarget = true,
            hasOfferedFreeTargetMoment = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Offer(grant), offered)
    }

    @Test
    fun freeWriterSecondCrossingSameDayShowsNoRepeat() {
        // hasOfferedFreeTargetMoment carries both the session flag and the
        // once-per-day ledger — either suppresses a repeat.
        val action = ladder.action(
            grant = null,
            unlockState = lockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = false,
            hasReachedDailyTarget = true,
            hasOfferedFreeTargetMoment = true,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Withdraw, action)
    }

    @Test
    fun lapsedWriterIsTreatedAsFree() {
        // A lapse narrows dailyUnlockEntitled to false — the same flag the
        // moment branch reads, so lapsed and never-subscribed are identical.
        val action = ladder.action(
            grant = quickGrant(startingAt = now),
            unlockState = activeQuickPassState,
            isGateOriginatedSession = true,
            hasAppliedPassiveQuickUnlock = true,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = false,
            hasReachedDailyTarget = true,
            hasOfferedFreeTargetMoment = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.OfferFreeTargetMoment, action)
    }

    @Test
    fun freeWriterBelowTargetNeverSeesTheMoment() {
        val action = ladder.action(
            grant = null,
            unlockState = lockedState,
            isGateOriginatedSession = false,
            hasAppliedPassiveQuickUnlock = false,
            hasAppliedDailyUnlockUpgrade = false,
            dailyUnlockEntitled = false,
            hasReachedDailyTarget = false,
            hasOfferedFreeTargetMoment = false,
            at = now,
        )
        assertEquals(WriteBeforeScrollUnlockLadderAction.Withdraw, action)
    }

    @Test
    fun freeTargetMomentLedgerIsOncePerDay() {
        val ledger = FreeTargetMomentLedger(FakeSharedPreferences(), ZoneOffset.UTC)
        assertFalse(ledger.wasShown(on = now))
        ledger.markShown(on = now)
        assertTrue(ledger.wasShown(on = now))
        assertTrue(ledger.wasShown(on = now.plusSeconds(3_600)))
        assertFalse(
            "a new day starts a new clock",
            ledger.wasShown(on = now.plusSeconds(48 * 3_600)),
        )
    }
}
