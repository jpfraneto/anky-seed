package inc.anky.android.core.gate.runtime

import inc.anky.android.core.gate.GateStateStore
import inc.anky.android.core.gate.QuickPassStore
import inc.anky.android.core.gate.RelockSchedulerPort
import inc.anky.android.core.gate.ShieldPort
import inc.anky.android.core.gate.UnlockGrant
import inc.anky.android.core.gate.UnlockStateStore
import inc.anky.android.core.gate.UnlockTier
import inc.anky.android.core.gate.WriteBeforeScrollEventLogStore
import inc.anky.android.core.gate.WriteBeforeScrollEventName
import inc.anky.android.core.gate.WriteBeforeScrollUnlockSource
import inc.anky.android.core.gate.WriteBeforeScrollUnlockStateMachine
import java.time.Instant
import java.time.ZoneId

/**
 * The one honest way to open the door — port of the iOS
 * `WriteBeforeScrollSpikeViewModel.applyUnlock` sequence, shared by the
 * emergency breath and (via the writing-surface workstream) the unlock
 * ladder actions:
 *
 *  1. gate-originated quick grants consume a Quick Pass (`quick_pass_used`),
 *  2. `UnlockStateStore.apply`,
 *  3. shield down ([ShieldPort.clearShield]),
 *  4. state machine `applyingUnlock`,
 *  5. `unlock_granted` with source + window,
 *  6. relock scheduled at `unlockedUntil`.
 */
class GateUnlockApplier(
    private val quickPassStore: QuickPassStore,
    private val unlockStateStore: UnlockStateStore,
    private val stateStore: GateStateStore,
    private val eventLog: WriteBeforeScrollEventLogStore,
    private val shieldPort: ShieldPort,
    private val relockScheduler: RelockSchedulerPort,
) {
    fun applyUnlock(
        grant: UnlockGrant,
        source: WriteBeforeScrollUnlockSource = WriteBeforeScrollUnlockSource.Writing,
    ) {
        if (grant.tier == UnlockTier.Quick && source == WriteBeforeScrollUnlockSource.Writing) {
            quickPassStore.consumePass(now = grant.grantedAt)?.let { passNumber ->
                eventLog.append(
                    WriteBeforeScrollEventName.QuickPassUsed,
                    at = grant.grantedAt,
                    tierRawValue = grant.tier.rawValue,
                    metadata = mapOf("passNumber" to "$passNumber"),
                )
            }
        }
        unlockStateStore.apply(grant)
        shieldPort.clearShield(now = grant.grantedAt)
        stateStore.update { state ->
            WriteBeforeScrollUnlockStateMachine.applyingUnlock(
                tierRawValue = grant.tier.rawValue,
                unlockedUntil = grant.unlockedUntil,
                source = source,
                state = state,
            )
        }
        eventLog.append(
            WriteBeforeScrollEventName.UnlockGranted,
            at = grant.grantedAt,
            tierRawValue = grant.tier.rawValue,
            metadata = mapOf(
                "source" to source.rawValue,
                "unlockedUntil" to grant.unlockedUntil.toString(),
            ),
        )
        relockScheduler.scheduleRelock(at = grant.unlockedUntil)
    }

    /**
     * Phase-2 §2, iOS `completeEmergencyBreath`: the breath finished —
     * everything opens until local midnight. No Quick Pass consumed, no
     * commentary; the `emergency` source is the whole record.
     */
    fun applyEmergencyUnlock(
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): UnlockGrant {
        val endOfDay = now.atZone(zoneId).toLocalDate().plusDays(1).atStartOfDay(zoneId).toInstant()
        val grant = UnlockGrant(
            tier = UnlockTier.Daily,
            unlockedUntil = endOfDay,
            grantedAt = now,
        )
        applyUnlock(grant, source = WriteBeforeScrollUnlockSource.Emergency)
        return grant
    }
}
