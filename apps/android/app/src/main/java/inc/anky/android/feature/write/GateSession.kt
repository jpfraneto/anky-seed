package inc.anky.android.feature.write

import android.content.SharedPreferences
import inc.anky.android.core.gate.DailyTargetStore
import inc.anky.android.core.gate.FirstGateStore
import inc.anky.android.core.gate.FreeTargetMomentLedger
import inc.anky.android.core.gate.GateWritingSnapshot
import inc.anky.android.core.gate.QuickPassStore
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockPolicy
import inc.anky.android.core.gate.UnlockState
import inc.anky.android.core.gate.UnlockStateStore
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollUnlockLadder
import inc.anky.android.core.gate.WriteBeforeScrollUnlockLadderAction
import inc.anky.android.core.gate.WriteBeforeScrollUnlockOfferPolicy
import java.time.Instant
import java.util.UUID

/**
 * The writing surface's one seam onto the Write Before You Scroll engine
 * (core/gate). WriteViewModel talks only to this facade, mirroring how iOS
 * WriteViewModel reaches for UnlockPolicy / QuickPassStore / DailyTargetStore /
 * UnlockStateStore / WriteBeforeScrollEventLogStore / FreeTargetMomentLedger /
 * FirstGateStore directly (ios/Anky/Features/Write/WriteViewModel.swift).
 *
 * Construction: `GateSession(GateStorage.preferences(context))` at the
 * integration site (AppContainer / AnkyApp — see android/WIRING-write.md).
 * When WriteViewModel receives no GateSession the ladder is simply inert,
 * which keeps today's AnkyApp call sites behaving as before.
 */
class GateSession(
    private val unlockStateStore: UnlockStateStore,
    private val quickPassStore: QuickPassStore,
    private val dailyTargetStore: DailyTargetStore,
    private val eventLog: WriteBeforeScrollEventLogStore,
    private val freeTargetMomentLedger: FreeTargetMomentLedger,
    private val firstGateStore: FirstGateStore,
    private val policy: UnlockPolicy = UnlockPolicy(),
    private val ladder: WriteBeforeScrollUnlockLadder = WriteBeforeScrollUnlockLadder(),
    private val offerPolicy: WriteBeforeScrollUnlockOfferPolicy = WriteBeforeScrollUnlockOfferPolicy(),
) {
    constructor(preferences: SharedPreferences) : this(
        unlockStateStore = UnlockStateStore(preferences),
        quickPassStore = QuickPassStore(preferences),
        dailyTargetStore = DailyTargetStore(preferences),
        eventLog = WriteBeforeScrollEventLogStore(preferences),
        freeTargetMomentLedger = FreeTargetMomentLedger(preferences),
        firstGateStore = FirstGateStore(preferences),
    )

    fun dailyTargetMs(at: Instant): Long = dailyTargetStore.effectiveTargetMs(now = at)

    fun quickPassesRemaining(at: Instant): Int = quickPassStore.remainingPasses(now = at)

    fun unlockState(): UnlockState = unlockStateStore.load()

    fun grant(
        snapshot: GateWritingSnapshot,
        at: Instant,
        dailyTargetMs: Long,
        quickPassesRemaining: Int,
        dailyUnlockEntitled: Boolean,
    ): UnlockGrant? = policy.grant(
        snapshot = snapshot,
        at = at,
        dailyTargetMs = dailyTargetMs,
        quickPassesRemaining = quickPassesRemaining,
        dailyUnlockEntitled = dailyUnlockEntitled,
    )

    fun ladderAction(
        grant: UnlockGrant?,
        isGateOriginatedSession: Boolean,
        hasAppliedPassiveQuickUnlock: Boolean,
        hasAppliedDailyUnlockUpgrade: Boolean,
        dailyUnlockEntitled: Boolean,
        hasReachedDailyTarget: Boolean,
        hasOfferedFreeTargetMoment: Boolean,
        at: Instant,
    ): WriteBeforeScrollUnlockLadderAction = ladder.action(
        grant = grant,
        unlockState = unlockStateStore.load(),
        isGateOriginatedSession = isGateOriginatedSession,
        hasAppliedPassiveQuickUnlock = hasAppliedPassiveQuickUnlock,
        hasAppliedDailyUnlockUpgrade = hasAppliedDailyUnlockUpgrade,
        dailyUnlockEntitled = dailyUnlockEntitled,
        hasReachedDailyTarget = hasReachedDailyTarget,
        hasOfferedFreeTargetMoment = hasOfferedFreeTargetMoment,
        at = at,
    )

    /**
     * §5.4 passive Quick Pass: spend the pass, open the window, log
     * `quick_pass_used` — the caller then fires `onApplyUnlock` so the
     * blocking runtime can clear the shield and schedule the relock.
     */
    fun applyQuickPassUnlock(grant: UnlockGrant, at: Instant, sessionId: UUID?) {
        quickPassStore.consumePass(now = at)
        unlockStateStore.apply(grant)
        eventLog.append(
            WriteBeforeScrollEventName.QuickPassUsed,
            at = at,
            sessionId = sessionId,
            tierRawValue = grant.tier.rawValue,
        )
    }

    /** Replaces the active window in place (daily upgrade / held grant). */
    fun applyGrant(grant: UnlockGrant) {
        unlockStateStore.apply(grant)
    }

    fun markWrote(at: Instant) {
        unlockStateStore.markWrote(at)
    }

    fun shouldOfferUnlock(at: Instant): Boolean =
        offerPolicy.shouldOfferUnlock(unlockStateStore.load(), at)

    fun wasFreeTargetMomentShown(at: Instant): Boolean = freeTargetMomentLedger.wasShown(at)

    fun markFreeTargetMomentShown(at: Instant) {
        freeTargetMomentLedger.markShown(at)
    }

    val hasCompletedFirstGate: Boolean
        get() = firstGateStore.hasCompletedFirstGate

    fun markFirstGateCompleted() {
        firstGateStore.markFirstGateCompleted()
    }

    fun log(
        name: WriteBeforeScrollEventName,
        at: Instant,
        sessionId: UUID? = null,
        tierRawValue: String? = null,
        metadata: Map<String, String> = emptyMap(),
    ) {
        eventLog.append(name, at = at, sessionId = sessionId, tierRawValue = tierRawValue, metadata = metadata)
    }
}
