package inc.anky.android.core.gate

import java.time.Instant

/**
 * Where iOS talks to ManagedSettings (`ScreenTimeShieldController`), Android
 * talks to this port. The blocking-runtime workstream implements it (usage
 * watcher + shield activity); the gate engine only decides.
 *
 * Implementations must log `shield_applied` / `shield_cleared` only on
 * transitions — use [WriteBeforeScrollEventLogStore.appendShieldTransition].
 */
interface ShieldPort {
    /** Arms the shield over the selected apps. Returns false when nothing is selected. */
    fun applyShield(now: Instant = Instant.now()): Boolean

    /** Takes the shield down. */
    fun clearShield(now: Instant = Instant.now())
}

/**
 * Where iOS schedules `ScreenTimeUnlockScheduler` relocks, Android schedules
 * an AlarmManager alarm at `unlockedUntil`. Belt-and-braces with the
 * foreground reconcile, mirroring the iOS reconciler philosophy.
 */
interface RelockSchedulerPort {
    fun scheduleRelock(at: Instant)

    fun cancelRelock()
}
